// flow-stack's mod: what bash hooks can't do.
//   - the flow band above the prompt, and the slice beside the spinner (state from skills/flow/scripts/status.sh)
//   - each flow-stack agent spawns on the model its role gets in the profile's budget:
//   - /flow-pane: the task's slices, open gates with Approve/Reject, and the other leads
import type { EngineInterface, Register } from 'claude-code'

type Status = {
  task?: string
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
}

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
  const parts = [`flow · ${s.task}`]
  if (s.slice) parts.push(`${s.slice.id} ${s.slice.title}`)
  if (s.total) parts.push(`${s.done}/${s.total} slices`)
  if (s.tdd) parts.push(`tdd ${s.tdd}`)
  if (s.evidence) {
    parts.push(`${s.evidence.label} ${s.evidence.verdict}${s.stale ? ' · edited since' : ''}`)
  }
  return parts.join(' · ')
}

let status: Status | null = null
let models: Partial<Record<Budget, string>> = {}
let paneOpen = false
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

// A gate button: record the decision, then tell Claude so it acts on it.
async function decide($: EngineInterface, n: number, question: string, verdict: 'approve' | 'reject') {
  const ran = await $.process.run([`${$.plugin.root}/skills/flow/scripts/task.sh`, 'gate', String(n), verdict], {
    cwd: await $.session.cwd(),
  })
  if (ran.exitCode !== 0) {
    $.ui.toast(`flow-stack: ${(ran.stderr || ran.stdout).trim()}`)
  } else {
    await $.prompt.submit({ text: `The human ${verdict}d gate ${n} in the /flow-pane: "${question}". Act on it.` })
  }
  await refresh($)
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
    paneOpen = true
    await $.ui.open({ id: PANE, title: 'flow' })
    void refresh($)
    return {}
  })

  on('ui.close', { id: PANE }, async ($, e, next) => {
    paneOpen = false
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    if (!status) return <Text dimColor>No active flow task. Start one with /flow-stack:flow.</Text>
    const { slices = [], gates = [], leads = [] } = status
    return (
      <Box flexDirection="column" gap={1}>
        <Text bold>{bandText(status)}</Text>
        <Box flexDirection="column">
          {slices.map(s => (
            <Text dimColor={s.status === 'done'}>
              {s.id} {s.title} · {s.status}
              {s.verdict ? ` · ${s.verdict}` : ''}
            </Text>
          ))}
        </Box>
        {gates.length > 0 && (
          <Box flexDirection="column">
            <Text bold>GATES</Text>
            {gates.map(g => (
              <Box key={`gate-${g.n}`} flexDirection="column">
                <Text>{g.question}</Text>
                {g.detail !== '' && <Text dimColor>{g.detail}</Text>}
                <Box gap={1}>
                  <Button key={`approve-${g.n}`} label="Approve" onPress={() => decide($, g.n, g.question, 'approve')} />
                  <Button key={`reject-${g.n}`} label="Reject" onPress={() => decide($, g.n, g.question, 'reject')} />
                </Box>
              </Box>
            ))}
          </Box>
        )}
        {leads.length > 1 && (
          <Box flexDirection="column">
            <Text bold>LEADS</Text>
            {leads.map(l => (
              <Text dimColor>
                {l.id} · {l.repo} · {l.branch}
                {l.task ? ` · ${l.task}` : ''}
                {l.slice ? ` ${l.slice}` : ''}
              </Text>
            ))}
          </Box>
        )}
      </Box>
    )
  })

  // evidence.sh, task.sh, and edits all change what the band shows
  on('tool.call', async ($, e, next) => {
    const ran = await next(e)
    if (/^(Bash|Edit|Write|MultiEdit)$/.test(e.tool)) void refresh($)
    return ran
  })

  on('turn.complete', async ($, e, next) => {
    void refresh($)
    return next(e)
  })

  on('agent.spawn', async ($, e, next) => {
    const role = ROLE[e.subagentType]
    const model = role && models[role]
    if (e.model || !model) return next(e)
    if (!toasted.has(e.subagentType)) {
      toasted.add(e.subagentType)
      $.ui.toast(`${e.subagentType.replace('flow-stack:', '')} → ${model}`)
    }
    return next({ ...e, model })
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
