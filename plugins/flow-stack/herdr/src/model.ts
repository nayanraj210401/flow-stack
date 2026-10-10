// The board's data: every Claude pane herdr runs, joined to the flow task its session owns.
// Pure functions only; src/herdr.ts does the reading and writing.

// One row of `herdr agent list`.
export type Agent = {
  pane_id: string
  agent: string
  agent_status: 'idle' | 'working' | 'blocked' | 'done' | 'unknown'
  cwd: string
  focused: boolean
  name?: string
  agent_session?: { value: string }
}

// One file of Claude Code's session registry, <config>/sessions/<pid>.json.
export type Session = { pid: number; sessionId: string; name?: string; status?: string }

export type Gate = { n: number; question: string; detail: string }
export type Slice = { id: string; title: string; status: string; verdict: string }

// skills/flow/scripts/status.sh --full <dir>
export type Status = {
  task?: string
  owner?: string
  slice?: { id: string; title: string } | null
  done?: number
  total?: number
  evidence?: { label: string; verdict: string; ts: string } | null
  stale?: boolean
  slices?: Slice[]
  gates?: Gate[]
  runs?: string[]
}

export type Row = {
  pane: string
  cwd: string
  session: string // the name SendMessage and ListAgents know it by
  state: Agent['agent_status']
  focused: boolean
  // the task this pane's session owns; null when it owns none
  task: (Status & { task: string }) | null
}

// rows: one per Claude pane. A pane shows a task only when its session owns it; a task whose owner
// is gone (or was never recorded) shows on every pane in its checkout.
export function rows(agents: Agent[], sessions: Session[], statusOf: (cwd: string) => Status): Row[] {
  const byId = new Map(sessions.map(s => [s.sessionId, s]))
  return agents
    .filter(a => a.agent === 'claude')
    .map(a => {
      const s = a.agent_session ? byId.get(a.agent_session.value) : undefined
      const st = statusOf(a.cwd)
      const mine = !!st.task && (st.owner ? String(s?.pid) === st.owner : true)
      return {
        pane: a.pane_id,
        cwd: a.cwd,
        session: s?.name ?? a.name ?? a.pane_id,
        state: a.agent_status,
        focused: a.focused,
        task: mine ? (st as Status & { task: string }) : null,
      }
    })
    .sort((x, y) => rank(x) - rank(y) || x.pane.localeCompare(y.pane))
}

// needs you first: open gates, then a blocked agent, then work in progress, then the rest
function rank(r: Row): number {
  if (r.task?.gates?.length) return 0
  if (r.state === 'blocked') return 1
  if (r.task && r.state === 'working') return 2
  if (r.task) return 3
  return 4
}

export type Option = { key: string; label: string }

// options: a gate's choices from its `options: A) … B) … (recommend: A, because …)` line.
export function options(g: Gate): { options: Option[]; recommend: string | null } {
  const line = g.detail.split(' · ').find(l => l.startsWith('options:'))
  if (!line) return { options: [], recommend: null }
  const body = line.slice('options:'.length)
  const rec = /\(recommend:\s*([A-Za-z0-9]+)\b/.exec(body)
  const list = body.replace(/\(recommend:[^)]*\)?/, '')
  const found = [...list.matchAll(/(?:^|\s)([A-Za-z0-9])\)\s+(.*?)(?=\s+[A-Za-z0-9]\)\s|$)/g)]
  return {
    options: found.map(m => ({ key: m[1]!, label: `${m[1]}) ${m[2]!.trim()}` })),
    recommend: rec ? rec[1]! : null,
  }
}

// tier: what backs a slice's state. Only a recorded PASS counts as verified.
export function tier(s: Slice): '◆' | '◇' | '✗' | '·' {
  if (s.verdict === 'PASS') return '◆'
  if (s.verdict === 'FAIL') return '✗'
  return s.status === 'done' ? '◇' : '·'
}
