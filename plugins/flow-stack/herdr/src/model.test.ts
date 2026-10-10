import { expect, test } from 'bun:test'
import { type Agent, type Session, type Status, options, rows, tier } from './model'

const agent = (pane: string, cwd: string, sid: string, state: Agent['agent_status'] = 'idle'): Agent =>
  ({ pane_id: pane, agent: 'claude', agent_status: state, cwd, focused: false, agent_session: { value: sid } })
const sessions: Session[] = [
  { pid: 11, sessionId: 's1', name: 'flow-1' },
  { pid: 22, sessionId: 's2', name: 'flow-2' },
  { pid: 33, sessionId: 's3', name: 'flow-3' },
]

test('a pane shows a task only when its session owns it', () => {
  const st: Record<string, Status> = { '/repo': { task: 'demo', owner: '11', gates: [] } }
  const r = rows([agent('w1:p1', '/repo', 's1'), agent('w1:p2', '/repo', 's2')], sessions, c => st[c] ?? {})
  expect(r.find(x => x.pane === 'w1:p1')?.task?.task).toBe('demo')
  expect(r.find(x => x.pane === 'w1:p2')?.task).toBeNull()
  expect(r.find(x => x.pane === 'w1:p2')?.session).toBe('flow-2')
})

test('a task with no live owner shows on its checkout', () => {
  const r = rows([agent('w1:p1', '/repo', 's1')], sessions, () => ({ task: 'demo', owner: '' }))
  expect(r[0]?.task?.task).toBe('demo')
})

test('needs you first: gates, then blocked, then working', () => {
  const st: Record<string, Status> = {
    '/a': { task: 'a', owner: '11', gates: [] },
    '/b': { task: 'b', owner: '22', gates: [{ n: 1, question: 'ship?', detail: '' }] },
    '/c': {},
  }
  const r = rows([agent('w1:p1', '/a', 's1', 'working'), agent('w1:p3', '/c', 's3', 'blocked'), agent('w1:p2', '/b', 's2')],
    sessions, c => st[c] ?? {})
  expect(r.map(x => x.pane)).toEqual(['w1:p2', 'w1:p3', 'w1:p1'])
})

test('other agents are left out', () => {
  const codex = { ...agent('w1:p9', '/x', 'sx'), agent: 'codex' }
  expect(rows([codex], sessions, () => ({}))).toEqual([])
})

test('options and the recommendation come from the options line', () => {
  const o = options({ n: 1, question: 'push?', detail: 'options: A) push now  B) hold   (recommend: A, because CI is green) · evidence: C1' })
  expect(o.options.map(x => x.label)).toEqual(['A) push now', 'B) hold'])
  expect(o.recommend).toBe('A')
  expect(options({ n: 2, question: 'x', detail: 'evidence: y' })).toEqual({ options: [], recommend: null })
})

test('evidence tiers: only a recorded PASS is verified', () => {
  expect(tier({ id: 'S1', title: '', status: 'done', verdict: 'PASS' })).toBe('◆')
  expect(tier({ id: 'S2', title: '', status: 'done', verdict: '' })).toBe('◇')
  expect(tier({ id: 'S3', title: '', status: 'doing', verdict: 'FAIL' })).toBe('✗')
  expect(tier({ id: 'S4', title: '', status: 'todo', verdict: '' })).toBe('·')
})
