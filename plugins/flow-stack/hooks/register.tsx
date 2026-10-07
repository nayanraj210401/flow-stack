// flow-stack's mod: what bash hooks can't do.
//   - the flow band above the prompt, and the slice beside the spinner (state from skills/flow/scripts/status.sh)
//   - each flow-stack agent spawns on the model its role gets in the profile's budget:
import type { EngineInterface, Register } from 'claude-code'

type Status = {
  task?: string
  slice: { id: string; title: string } | null
  done: number
  total: number
  tdd: string
  evidence: { label: string; verdict: string; ts: string } | null
  stale: boolean
}

type Budget = 'subagent_model' | 'build_model' | 'design_model'

// An agent the Agent call names without a model runs on the model its role gets.
const ROLE: Record<string, Budget> = {
  'flow-stack:advocate': 'design_model',
  'flow-stack:reviewer': 'design_model',
  'flow-stack:worker': 'build_model',
  'flow-stack:checker': 'build_model',
  'flow-stack:flow-agent': 'build_model',
  Explore: 'subagent_model',
}

// The profile's frontmatter `budget:` block: "  build_model: sonnet   # comment"
export function parseBudget(profile: string): Partial<Record<Budget, string>> {
  const out: Partial<Record<Budget, string>> = {}
  for (const m of profile.matchAll(/^\s+(subagent_model|build_model|design_model):\s*([^\s#]+)/gm)) {
    out[m[1] as Budget] = m[2]
  }
  return out
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
let running = false
let again = false

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
      const { stdout } = await $.process.run([`${$.plugin.root}/skills/flow/scripts/status.sh`, await $.session.cwd()])
      const next = JSON.parse(stdout || '{}') as Status
      status = next.task ? next : null
      $.ui.invalidate('ui.render')
    } while (again)
  } catch {
    status = null
  } finally {
    running = false
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const home = (await $.env.get('FLOW_STACK_HOME')) ?? `${await $.env.get('HOME')}/.flow-stack`
    models = parseBudget(await $.fs.read(`${home}/profile.md`).catch(() => ''))
    await refresh($)
    return next(e)
  })

  // evidence.sh, task.sh, and edits all change what the band shows
  on('tool.call', async ($, e, next) => {
    const ran = await next(e)
    if (/^(Bash|Edit|Write|MultiEdit)$/.test(e.tool)) void refresh($)
    return ran
  }).catch(($, e, next) => next(e))

  on('turn.complete', async ($, e, next) => {
    void refresh($)
    return next(e)
  })

  on('agent.spawn', async ($, e, next) => {
    const role = ROLE[e.subagentType]
    const model = role && models[role]
    return e.model || !model ? next(e) : next({ ...e, model })
  }).catch(($, e, next) => next(e))

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
