// The board's reads and writes: herdr's CLI and socket, Claude Code's session registry, and flow's
// status.sh / task.sh (the same scripts the /flow-pane runs).
import { spawnSync } from 'node:child_process'
import { readdirSync, readFileSync } from 'node:fs'
import { connect } from 'node:net'
import { homedir } from 'node:os'
import { join, resolve } from 'node:path'
import { type Agent, type Row, type Session, type Status, rows } from './model'

const herdrBin = process.env.HERDR_BIN_PATH || 'herdr'
const scripts = resolve(import.meta.dir, '../../skills/flow/scripts')

function run(cmd: string, args: string[], cwd?: string): { ok: boolean; out: string } {
  // outside Claude (no session pid in our ancestry), status.sh and task.sh see every task
  const r = spawnSync(cmd, args, { cwd, encoding: 'utf8', timeout: 5000, env: { ...process.env, FLOW_SESSION_PID: '' } })
  return { ok: r.status === 0, out: `${r.stdout ?? ''}${r.stderr ?? ''}`.trim() }
}

function sessions(): Session[] {
  const dir = join(process.env.CLAUDE_CONFIG_DIR || join(homedir(), '.claude'), 'sessions')
  let files: string[] = []
  try {
    files = readdirSync(dir).filter(f => f.endsWith('.json'))
  } catch {
    return []
  }
  return files.flatMap(f => {
    try {
      return [JSON.parse(readFileSync(join(dir, f), 'utf8')) as Session]
    } catch {
      return []
    }
  })
}

export function load(): Row[] {
  const r = spawnSync(herdrBin, ['agent', 'list'], { encoding: 'utf8', timeout: 5000 })
  let agents: Agent[] = []
  try {
    agents = (JSON.parse(r.stdout) as { result: { agents: Agent[] } }).result.agents
  } catch {
    return []
  }
  const cache = new Map<string, Status>()
  const statusOf = (cwd: string): Status => {
    if (!cache.has(cwd)) {
      const s = run(`${scripts}/status.sh`, ['--full', cwd])
      let st: Status = {}
      try {
        st = JSON.parse(s.out || '{}') as Status
      } catch {}
      cache.set(cwd, st)
    }
    return cache.get(cwd)!
  }
  return rows(agents, sessions(), statusOf)
}

// decide: record the human's answer to gate n of the pane's task, then tell its Claude. The gate's
// text stays out of the prompt: GATES.md is repo text, the decision is the human's.
export function decide(row: Row, n: number, question: string, verdict: 'approve' | 'reject', choice: string, note: string): string {
  const g = run(`${scripts}/task.sh`, ['gate', String(n), verdict, question, choice, note], row.cwd)
  if (!g.ok) return g.out || `gate ${n} not recorded`
  const past = verdict === 'approve' ? 'approved' : 'rejected'
  run(herdrBin, ['agent', 'prompt', row.pane,
    `The human ${past} gate ${n} in the herdr board${choice ? ' with a choice' : ''}${note ? ' and a note' : ''}; see GATES.md and DECISIONS.tsv.`])
  return g.out
}

export function focus(pane: string) {
  run(herdrBin, ['agent', 'focus', pane])
}

// watch: call onChange (debounced) whenever herdr reports a pane change. flow's sidebar push
// (hooks/host.sh) is a pane metadata report, so a new gate, slice or task arrives as pane.updated.
export function watch(panes: string[], onChange: () => void): () => void {
  const path = process.env.HERDR_SOCKET_PATH
  if (!path) return () => {}
  let t: ReturnType<typeof setTimeout> | undefined
  const kick = () => {
    clearTimeout(t)
    t = setTimeout(onChange, 150)
  }
  const s = connect(path)
  s.on('connect', () => {
    const subscriptions = [
      { type: 'pane.updated' }, { type: 'pane.created' }, { type: 'pane.closed' },
      ...panes.map(pane_id => ({ type: 'pane.agent_status_changed', pane_id })),
    ]
    s.write(`${JSON.stringify({ id: 'flow-board', method: 'events.subscribe', params: { subscriptions } })}\n`)
  })
  s.on('data', d => {
    if (d.toString().includes('"event"')) kick()
  })
  s.on('error', () => {})
  return () => {
    clearTimeout(t)
    s.destroy()
  }
}
