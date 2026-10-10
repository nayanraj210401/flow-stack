import { expect, test } from 'bun:test'
import { render } from 'ink-testing-library'
import React from 'react'
import type { Row } from './model'
import { Board, DecideFocused, type Io } from './ui'

const tick = () => new Promise(r => setTimeout(r, 30))
const gated: Row = {
  pane: 'w1:p2', cwd: '/repo', session: 'flow-2', state: 'working', focused: false,
  task: {
    task: 'ship-it', owner: '22', slice: { id: 'S2', title: 'push' }, done: 1, total: 2,
    evidence: { label: 'S1', verdict: 'PASS', ts: 't' }, stale: false,
    slices: [{ id: 'S1', title: 'build', status: 'done', verdict: 'PASS' }, { id: 'S2', title: 'push', status: 'doing', verdict: '' }],
    gates: [{ n: 1, question: 'push the branch?', detail: 'options: A) push now  B) hold   (recommend: B, because CI is red) · evidence: C1' }],
    runs: ['FAIL', 'PASS'],
  },
}
const idle: Row = { pane: 'w1:p1', cwd: '/other', session: 'flow-1', state: 'idle', focused: true, task: null }

function fakeIo(list: Row[]) {
  const calls: { decide: unknown[][]; focus: string[]; watched: string[][] } = { decide: [], focus: [], watched: [] }
  const io: Io = {
    load: () => list,
    decide: (...a) => { calls.decide.push(a); return `gate ${a[1]} ${a[3]}d` },
    focus: p => { calls.focus.push(p) },
    watch: (panes) => { calls.watched.push(panes); return () => {} },
  }
  return { io, calls }
}

test('board lists every pane, needs-you marked, with the selected task in detail', async () => {
  const { io, calls } = fakeIo([gated, idle])
  const ui = render(<Board io={io} />)
  await tick()
  const f = ui.lastFrame()!
  expect(f).toContain('⚑ 1 gate(s)')
  expect(f).toContain('ship-it')
  expect(f).toContain('(no task)')
  expect(f).toContain('◆ S1 build')
  expect(f).toContain('push the branch?')
  expect(calls.watched.at(-1)).toEqual(['w1:p2', 'w1:p1'])
  ui.unmount()
})

test('d opens the gate with the recommended option selected; enter records it with the note', async () => {
  const { io, calls } = fakeIo([gated, idle])
  const ui = render(<Board io={io} />)
  await tick()
  ui.stdin.write('d'); await tick()
  expect(ui.lastFrame()).toContain('▸ B) hold (recommended)')
  ui.stdin.write('n'); await tick()
  for (const c of 'after review') ui.stdin.write(c)
  await tick()
  ui.stdin.write('\r'); await tick()
  ui.stdin.write('\r'); await tick()
  expect(calls.decide).toEqual([[gated, 1, 'push the branch?', 'approve', 'B) hold', 'after review']])
  expect(ui.lastFrame()).toContain('gate 1 approved')
  ui.unmount()
})

test('reject is the last choice', async () => {
  const { io, calls } = fakeIo([gated])
  const ui = render(<Board io={io} />)
  await tick()
  ui.stdin.write('d'); await tick()
  ui.stdin.write('j'); await tick()
  ui.stdin.write('\r'); await tick()
  expect(calls.decide[0]?.slice(3)).toEqual(['reject', '', ''])
  ui.unmount()
})

test('enter on a row jumps to its pane', async () => {
  const { io, calls } = fakeIo([gated, idle])
  const ui = render(<Board io={io} />)
  await tick()
  ui.stdin.write('j'); await tick()
  ui.stdin.write('\r'); await tick()
  expect(calls.focus).toEqual(['w1:p1'])
  ui.unmount()
})

test('decide on a key: the focused pane\'s gate, or a plain note when it has none', async () => {
  const { io } = fakeIo([gated, idle])
  const a = render(<DecideFocused io={io} pane="w1:p2" />)
  await tick()
  expect(a.lastFrame()).toContain('push the branch?')
  a.unmount()
  const b = render(<DecideFocused io={io} pane="w1:p1" />)
  await tick()
  expect(b.lastFrame()).toContain('No open gate on this pane')
  b.unmount()
})
