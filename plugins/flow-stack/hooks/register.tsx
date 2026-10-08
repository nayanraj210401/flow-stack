// flow-stack's mod: what bash hooks can't do.
//   - the flow band above the prompt, and the slice beside the spinner (state from skills/flow/scripts/status.sh)
//   - each flow-stack agent spawns on the model its role gets in the profile's budget:
//   - /flow-pane: the task's slices, open gates with Approve/Reject, the other leads, this session's
//     subagents, the evidence history, and context and cost gauges, animated while open
import type { EngineInterface, Register, SessionUsage, Timer } from 'claude-code'

type Status = {
  task?: string
  where?: 'main' | 'lead' | 'lane'
  slice: { id: string; title: string } | null
  done: number
  total: number
  tdd: string
  evidence: { label: string; verdict: string; ts: string } | null
  stale: boolean
  // with status.sh --full, while the pane is open
  slices?: { id: string; title: string; status: string; verdict: string }[]
  gates?: { n: number; question: string; detail: string }[]
  leads?: { id: string; repo: string; branch: string; task: string; slice: string }[]
  runs?: string[]
  est_usd?: number | null
}

// A subagent this session spawned: started at agent.spawn, counted on each tool.call it makes,
// ended at its turn.complete.
type Lane = { role: string; model: string; what: string; start: number; tools: number; end?: number; ok?: boolean }

const PANE = 'flow-pane'

type Budget = 'subagent_model' | 'build_model' | 'design_model'

// A flow-stack agent the Agent call names without a model runs on the model its role gets.
// Only flow-stack's own agents: built-ins like Explore keep Claude Code's choice.
const ROLE: Record<string, Budget> = {
  'flow-stack:advocate': 'design_model',
  'flow-stack:reviewer': 'design_model',
  'flow-stack:worker': 'build_model',
  'flow-stack:checker': 'build_model',
  'flow-stack:flow-agent': 'build_model',
}

// A model alias, or a full id from the API, Bedrock (us.anthropic.claude-…, ARNs), or Vertex (claude-…@date).
const MODEL = /^(haiku|sonnet|opus|fable|inherit|[\w.:@\/-]*claude[\w.:@\/-]*)(\[1m\])?$/

// The profile's frontmatter `budget:` block ("  build_model: sonnet   # comment"). A value that
// isn't a model is dropped into `rejected`, so a typo leaves the spawn on Claude Code's choice.
export function parseBudget(profile: string) {
  const models: Partial<Record<Budget, string>> = {}
  const rejected: string[] = []
  const front = /^---\r?\n([\s\S]*?)\r?\n---/.exec(profile)?.[1] ?? ''
  for (const m of front.matchAll(/^[ \t]+(subagent_model|build_model|design_model):[ \t]*([^\s#]+)/gm)) {
    const [, key, value] = m as unknown as [string, Budget, string]
    if (MODEL.test(value)) models[key] = value
    else rejected.push(`${key}: ${value}`)
  }
  return { models, rejected }
}

export function bandText(s: Status): string {
  const parts = [`flow · ${s.where === 'lane' ? 'lane of ' : ''}${s.task}`]
  if (s.slice) parts.push(`${s.slice.id} ${s.slice.title}`)
  if (s.total) parts.push(`${s.done}/${s.total} slices`)
  if (s.tdd) parts.push(`tdd ${s.tdd}`)
  if (s.evidence) {
    parts.push(`${s.evidence.label} ${s.evidence.verdict}${s.stale ? ' · edited since' : ''}`)
  }
  return parts.join(' · ')
}

const SPIN = '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
const EIGHTHS = ' ▏▎▍▌▋▊▉'
const FRAME_MS = 100

// A progress bar `width` cells wide, filled to `fraction` in eighths of a cell.
export function bar(fraction: number, width: number): string {
  const eighths = Math.round(Math.min(1, Math.max(0, fraction)) * width * 8)
  const full = Math.floor(eighths / 8)
  const part = eighths % 8 ? EIGHTHS[eighths % 8] : ''
  return '█'.repeat(full) + part + '░'.repeat(width - full - (part ? 1 : 0))
}

export const spin = (frame: number) => SPIN[frame % SPIN.length]

// Consecutive equal verdicts as one run of ■, so the strip is a few Texts, not forty.
export function strip(runs: string[]): { verdict: string; cells: string }[] {
  const out: { verdict: string; cells: string }[] = []
  for (const v of runs) {
    const last = out.at(-1)
    if (last?.verdict === v) last.cells += '■'
    else out.push({ verdict: v, cells: '■' })
  }
  return out
}

export function laneText(l: Lane, now: number): string {
  const secs = Math.max(0, Math.round(((l.end ?? now) - l.start) / 1000))
  return `${l.role.padEnd(10)} ${l.model.padEnd(7)} ${l.what}  ${secs}s · ${l.tools} tools`
}

const LANE_LINGER_MS = 8000

// Drops lanes that ended more than LANE_LINGER_MS ago; called wherever the clock is read.
function prune(t: number) {
  now = t
  for (const [id, l] of lanes) if (l.end !== undefined && t - l.end > LANE_LINGER_MS) lanes.delete(id)
}

// The pane's animation: a frame count, the bar easing toward done/total, rows fading in after open.
let frame = 0
let openedAt = 0
let shown = 0
let ticker: Timer | null = null
let now = 0
let usage: SessionUsage | null = null
const lanes = new Map<string, Lane>()

let status: Status | null = null
let models: Partial<Record<Budget, string>> = {}
let paneOpen = false
const deciding = new Set<number>()
let running = false
let again = false
const toasted = new Set<string>()

// Re-read the task's state; calls that land while one runs fold into one more pass.
async function refresh($: EngineInterface) {
  if (running) {
    again = true
    return
  }
  running = true
  try {
    do {
      again = false
      try {
        const args = [...(paneOpen ? ['--full'] : []), await $.session.cwd()]
        const { stdout } = await $.process.run([`${$.plugin.root}/skills/flow/scripts/status.sh`, ...args])
        const next = JSON.parse(stdout || '{}') as Status
        status = next.task ? next : null
      } catch {
        status = null
      }
      $.ui.invalidate('ui.render')
    } while (again)
  } finally {
    running = false
  }
}

// A gate button: record the decision (only if gate n still reads as shown), then tell Claude.
// The question stays out of the prompt: GATES.md is repo text, the decision is the human's.
async function decide($: EngineInterface, n: number, question: string, verdict: 'approve' | 'reject') {
  if (deciding.has(n)) return
  deciding.add(n)
  try {
    const ran = await $.process.run(
      [`${$.plugin.root}/skills/flow/scripts/task.sh`, 'gate', String(n), verdict, question],
      { cwd: await $.session.cwd() },
    )
    if (ran.exitCode !== 0) {
      $.ui.toast(`flow-stack: ${(ran.stderr || ran.stdout).trim()}`)
    } else {
      const past = verdict === 'approve' ? 'approved' : 'rejected'
      await $.prompt.submit({ text: `The human ${past} gate ${n} in the /flow-pane; see GATES.md and DECISIONS.tsv.` })
    }
  } finally {
    deciding.delete(n)
    await refresh($)
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const home = (await $.env.get('FLOW_STACK_HOME')) ?? `${await $.env.get('HOME')}/.flow-stack`
    const budget = parseBudget(await $.fs.read(`${home}/profile.md`).catch(() => ''))
    models = budget.models
    if (budget.rejected.length) {
      $.ui.toast(`flow-stack: ignoring budget ${budget.rejected.join(', ')} (not a model name)`, { timeoutMs: 10000 })
    }
    await $.command.register({ name: 'flow-pane', description: "Open flow-stack's pane: slices, gates to approve, leads" })
    void refresh($)
    return next(e)
  })

  on('command.run', { command: 'flow-pane' }, async $ => {
    await $.ui.open({ id: PANE, title: 'flow' })
    paneOpen = true
    openedAt = frame
    shown = 0
    ticker ??= $.clock.every(FRAME_MS, () => {
      frame++
      const target = status?.total ? status.done / status.total : 0
      shown = Math.abs(target - shown) < 0.005 ? target : shown + (target - shown) * 0.25
      void $.clock.now().then(prune)
      if (frame % 10 === 1) void $.session.usage().then(u => (usage = u), () => {})
      $.ui.invalidate('ui.render')
    })
    void refresh($)
    return {}
  })

  on('ui.close', { id: PANE }, async ($, e, next) => {
    const closed = await next(e)
    paneOpen = false
    ticker?.cancel()
    ticker = null
    return closed
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const { slices = [], gates = [], leads = [], runs = [], est_usd = null } = status ?? {}
    const age = frame - openedAt
    const pulse = Math.floor(frame / 5) % 2 === 0
    // row i fades in on frame i after the pane opens
    const faded = (i: number) => age <= i
    const verdictColor = (v: string) => (v === 'PASS' ? 'success' : v === 'FAIL' ? 'error' : 'subtle')
    const ctx = usage?.context.percent
    const usd = usage?.cost?.usd
    const agents = [...lanes.entries()]
    const busy = agents.filter(([, l]) => l.end === undefined).length
    return (
      <Box flexDirection="column" gap={1}>
        {status ? (
          <Box gap={1}>
            <Text color="claude">{spin(frame)}</Text>
            <Text bold>{bandText(status)}</Text>
          </Box>
        ) : (
          <Text dimColor>No active flow task. Start one with /flow-stack:flow.</Text>
        )}
        {status && status.total > 0 && (
          <Box gap={1}>
            <Text color="claude">{bar(shown, 24)}</Text>
            <Text dimColor>
              {status.done}/{status.total}
            </Text>
          </Box>
        )}
        <Box flexDirection="column">
          {slices.map((s, i) => {
            const active = s.id === status?.slice?.id && s.status !== 'done'
            const icon = s.status === 'done' ? '✓' : active ? spin(frame + i) : '○'
            const iconColor = faded(i) ? 'subtle' : s.status === 'done' ? 'success' : active ? 'claude' : 'subtle'
            return (
              <Box key={`slice-${s.id}`} gap={1}>
                <Text color={iconColor}>{icon}</Text>
                <Text dimColor={faded(i) || s.status === 'done'} bold={active && !faded(i)}>
                  {s.id} {s.title} · {s.status}
                </Text>
                {s.verdict !== '' && <Text color={faded(i) ? 'subtle' : verdictColor(s.verdict)}>{s.verdict}</Text>}
              </Box>
            )
          })}
        </Box>
        {runs.length > 0 && (
          <Box gap={1}>
            <Box>
              {strip(runs).map((g, i) => (
                <Text key={`run-${i}`} color={verdictColor(g.verdict)}>
                  {g.cells}
                </Text>
              ))}
            </Box>
            <Text dimColor>
              last {runs.length} checks · {runs.filter(v => v === 'PASS').length} pass
            </Text>
          </Box>
        )}
        {(ctx !== undefined || usd !== undefined) && (
          <Box flexDirection="column">
            {ctx !== undefined && (
              <Box gap={1}>
                <Text color={ctx >= 80 ? 'error' : ctx >= 60 ? 'warning' : 'success'}>{bar(ctx / 100, 24)}</Text>
                <Text dimColor>context {Math.round(ctx)}%</Text>
              </Box>
            )}
            {usd !== undefined && (
              <Text dimColor>
                ${usd.toFixed(2)} this session{est_usd ? ` · task est $${est_usd.toFixed(2)}` : ''}
              </Text>
            )}
          </Box>
        )}
        {agents.length > 0 && (
          <Box flexDirection="column">
            <Text bold>AGENTS · {busy} running</Text>
            {agents.map(([id, l], i) => (
              <Box key={`agent-${id}`} gap={1}>
                <Text color={l.end === undefined ? 'claude' : l.ok ? 'success' : 'error'}>
                  {l.end === undefined ? spin(frame + i * 2) : l.ok ? '✓' : '✗'}
                </Text>
                <Text dimColor={l.end !== undefined} wrap="truncate-end">
                  {laneText(l, now)}
                </Text>
              </Box>
            ))}
          </Box>
        )}
        {gates.length > 0 && (
          <Box flexDirection="column">
            <Text bold color={pulse ? 'warning' : 'subtle'}>
              {pulse ? '◆' : '◇'} GATES · {gates.length} waiting on you
            </Text>
            {gates.map(g => (
              <Box key={`gate-${g.n}`} flexDirection="column">
                <Text>{g.question}</Text>
                {g.detail !== '' && <Text dimColor>{g.detail}</Text>}
                <Box gap={1}>
                  <Button key={`approve-${g.n}`} label="Approve" onPress={() => decide($, g.n, g.question, 'approve')} />
                  <Button key={`reject-${g.n}`} label="Reject" onPress={() => decide($, g.n, g.question, 'reject')} />
                  {deciding.has(g.n) && <Text color="claude">{spin(frame)} recording…</Text>}
                </Box>
              </Box>
            ))}
          </Box>
        )}
        {leads.length > 0 && (
          <Box flexDirection="column">
            <Text bold>LEADS</Text>
            {leads.map((l, i) => (
              <Box key={`lead-${l.id}`} gap={1}>
                <Text color={Math.floor((frame + i * 3) / 4) % 2 === 0 ? 'success' : 'subtle'}>●</Text>
                <Text dimColor>
                  {l.id} · {l.repo} · {l.branch}
                  {l.task ? ` · ${l.task}` : ''}
                  {l.slice ? ` ${l.slice}` : ''}
                </Text>
              </Box>
            ))}
          </Box>
        )}
      </Box>
    )
  })

  // evidence.sh, task.sh, and edits all change what the band shows
  on('tool.call', async ($, e, next) => {
    const lane = e.agentId ? lanes.get(e.agentId) : undefined
    if (lane) lane.tools++
    const ran = await next(e)
    if (/^(Bash|Edit|Write|MultiEdit)$/.test(e.tool)) void refresh($)
    return ran
  })

  on('turn.complete', async ($, e, next) => {
    const lane = e.agentId ? lanes.get(e.agentId) : undefined
    if (lane) {
      lane.end = await $.clock.now()
      lane.ok = e.reason === 'answer'
      prune(lane.end)
    }
    void refresh($)
    return next(e)
  })

  on('agent.spawn', async ($, e, next) => {
    const role = ROLE[e.subagentType]
    const model = !e.model && role ? models[role] : undefined
    if (model && !toasted.has(e.subagentType)) {
      toasted.add(e.subagentType)
      $.ui.toast(`${e.subagentType.replace('flow-stack:', '')} → ${model}`)
    }
    const started = await next(model ? { ...e, model } : e)
    if (started.agentId) {
      const what = e.description || e.subagentType
      const start = await $.clock.now()
      prune(start)
      lanes.set(started.agentId, { role: e.subagentType.replace('flow-stack:', ''), model: started.model, what, start, tools: 0 })
    }
    return started
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (!status || e.props.hasSurvey) return next(e)
    const { Text } = $.ui.resolve(e)
    return <Text dimColor wrap="truncate-end">{bandText(status)}</Text>
  })

  on('ui.render', { component: 'Spinner' }, async ($, e, next) => {
    const s = status?.slice
    if (!s) return next(e)
    const tdd = status?.tdd ? ` · ${status.tdd}` : ''
    return next({ ...e, props: { ...e.props, suffix: ` · ${s.id}${tdd}…` } })
  })
}
