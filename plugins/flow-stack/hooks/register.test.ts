import { expect, mock, test } from 'claude-code/testing'

import { bandText, bar, parseBudget, spin, strip } from './register'

const PROFILE = `---
budget:
  subagent_model: haiku           # exploration
  build_model: sonnet             # workers
  design_model: opus              # review
---
`

const STATUS = {
  task: 'rate-limit',
  slice: { id: 'S2', title: 'token bucket' },
  done: 1,
  total: 3,
  tdd: 'red',
  evidence: { label: 'S2:red', verdict: 'FAIL', ts: '2026-10-07T05:00:00Z' },
  stale: false,
}

test('parseBudget reads the profile budget block', () => {
  expect(parseBudget(PROFILE)).toEqual({
    models: { subagent_model: 'haiku', build_model: 'sonnet', design_model: 'opus' },
    rejected: [],
  })
})

test('parseBudget drops a value that is not a model name', () => {
  const typo = PROFILE.replace('build_model: sonnet', 'build_model: sonet').replace('design_model: opus', 'design_model: claude-opus-5-5[1m]')
  expect(parseBudget(typo)).toEqual({
    models: { subagent_model: 'haiku', design_model: 'claude-opus-5-5[1m]' },
    rejected: ['build_model: sonet'],
  })
})

test('bandText shows task, slice, progress, tdd phase, and evidence freshness', () => {
  expect(bandText(STATUS)).toBe('flow · rate-limit · S2 token bucket · 1/3 slices · tdd red · S2:red FAIL')
  expect(bandText({ ...STATUS, where: 'lane' })).toMatch(/^flow · lane of rate-limit · /)
  expect(bandText({ ...STATUS, stale: true })).toContain('S2:red FAIL · edited since')
})

// Starts a session whose profile is PROFILE and whose status.sh prints `status`.
async function start($: any, on: any, status: object = {}, profile = PROFILE) {
  on('fs.read', async () => ({ value: profile }))
  on('process.run', async () => ({ value: { exitCode: 0, stdout: JSON.stringify(status), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('env.get', async () => ({ value: '/home/me' }))
  on('session.cwd', async () => ({ value: '/tmp' }))
  on('session.start', async (_$: unknown, e: unknown) => e)
  on('command.register', async () => ({ value: undefined }))
  await $.session.start({ cwd: '/tmp', surface: null, isInteractive: false })
}

async function spawnWith($: any, on: any, args: { subagentType: string; model?: string }, profile = PROFILE) {
  let model: string | undefined
  on('agent.spawn', async (_$: unknown, e: { model?: string }) => {
    model = e.model
    return { model: e.model ?? 'inherit' }
  })
  await start($, on, {}, profile)
  await $.agent.spawn({ prompt: 'go', ...args })
  return model
}

for (const [type, want] of [
  ['flow-stack:worker', 'sonnet'],
  ['flow-stack:checker', 'sonnet'],
  ['flow-stack:flow-agent', 'sonnet'],
  ['flow-stack:reviewer', 'opus'],
  ['flow-stack:advocate', 'opus'],
] as const) {
  test(`agent.spawn puts ${type} on ${want}`, async ($, on) => {
    expect(await spawnWith($, on, { subagentType: type })).toBe(want)
  })
}

test('agent.spawn keeps a model the Agent call named', async ($, on) => {
  expect(await spawnWith($, on, { subagentType: 'flow-stack:worker', model: 'opus' })).toBe('opus')
})

test('parseBudget takes Bedrock and Vertex ids and ignores keys outside the frontmatter', () => {
  const ids = PROFILE.replace('build_model: sonnet', 'build_model: us.anthropic.claude-sonnet-4-5-20250929-v1:0')
    .replace('design_model: opus', 'design_model: claude-opus-4-1@20250805') + '\n# Notes\n  subagent_model: sonet\n'
  expect(parseBudget(ids)).toEqual({
    models: {
      subagent_model: 'haiku',
      build_model: 'us.anthropic.claude-sonnet-4-5-20250929-v1:0',
      design_model: 'claude-opus-4-1@20250805',
    },
    rejected: [],
  })
})

test('parseBudget reads a CRLF profile', () => {
  expect(parseBudget(PROFILE.replace(/\n/g, '\r\n')).models.build_model).toBe('sonnet')
})

test('agent.spawn leaves a worker on the default when build_model is a typo', async ($, on) => {
  const typo = PROFILE.replace('build_model: sonnet', 'build_model: sonet')
  expect(await spawnWith($, on, { subagentType: 'flow-stack:worker' }, typo)).toBe(undefined)
})

for (const type of ['general-purpose', 'Explore']) {
  test(`agent.spawn leaves ${type} alone`, async ($, on) => {
    expect(await spawnWith($, on, { subagentType: type })).toBe(undefined)
  })
}

const BAND = { component: 'AbovePrompt', props: { hasSurvey: false, isWorking: false, maxRows: 4, bodyColumns: 100 } } as const

test('the band shows the active task on every surface', async ($, on) => {
  let ran!: () => void
  const refreshed = new Promise<void>(r => (ran = r))
  on('ui.invalidate', async () => {
    ran()
    return { value: undefined }
  })
  await start($, on, STATUS)
  await refreshed
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'flow-stack', surface, ...BAND } as any)
    expect(await ui.find({ type: 'Text', text: /flow · rate-limit · S2 token bucket/ })).toBeDefined()
    await ui.unmount()
  }
})

test("the pane says whose task this checkout's is when another live session owns it", async ($, hooks) => {
  const on = hooks as any
  let ran!: () => void
  let refreshed = new Promise<void>(r => (ran = r))
  on('ui.invalidate', async () => {
    ran()
    return { value: undefined }
  })
  on('ui.open', async () => ({ value: { id: 'flow-pane' } }))
  await start($, on, { foreign: { task: 'script-bug-hunt', owner: 'flow-stack-88' } })
  await refreshed
  refreshed = new Promise<void>(r => (ran = r))
  await ($ as any).command.run({ command: 'flow-pane' })
  await refreshed
  const pane = await $.ui.mount({ plugin: 'flow-stack', surface: 'terminal', ...PANE } as any)
  expect(await pane.find({ type: 'Text', text: /script-bug-hunt here belongs to flow-stack-88/ })).toBeDefined()
  await pane.unmount()
})

const FULL = {
  ...STATUS,
  slices: [
    { id: 'S1', title: 'bucket', status: 'done', verdict: 'PASS' },
    { id: 'S2', title: 'token bucket', status: 'doing', verdict: 'FAIL' },
  ],
  gates: [{ n: 2, question: 'merge PR #3', detail: 'options: A) merge  B) wait' }],
  tasks: [{ task: 'search', where: 'wt-search', owner: 'flow-stack-ab', status: 'idle', live: true }],
}
const PANE = { component: 'Pane', requestId: 'flow-pane', props: { title: 'flow', isFocused: true, bodyColumns: 80, placement: 'dock' } } as const

test('/flow-pane opens a pane with slices and gates; Approve records the gate and tells Claude', async ($, hooks) => {
  const on = hooks as any
  const runs: (readonly string[])[] = []
  const said: string[] = []
  let ran!: () => void
  let refreshed = new Promise<void>(r => (ran = r))
  on('fs.read', async () => ({ value: PROFILE }))
  on('process.run', async (_$: unknown, e: { argv: readonly string[] }) => {
    runs.push(e.argv)
    const out = e.argv[1] === 'gate' ? 'gate 2 approved: merge PR #3' : JSON.stringify(e.argv.includes('--full') ? FULL : STATUS)
    return { value: { exitCode: 0, stdout: out, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('env.get', async () => ({ value: '/home/me' }))
  on('session.cwd', async () => ({ value: '/tmp' }))
  on('session.start', async (_$: unknown, e: unknown) => e)
  on('command.register', async () => ({ value: undefined }))
  on('ui.open', async () => ({ value: { id: 'flow-pane' } }))
  on('ui.invalidate', async () => {
    ran()
    return { value: undefined }
  })
  on('prompt.submit', async (_$: unknown, e: { text: string }) => {
    said.push(e.text)
    return { text: e.text }
  })
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })
  await refreshed
  refreshed = new Promise<void>(r => (ran = r))
  await ($ as any).command.run({ command: 'flow-pane' })
  await refreshed
  expect(runs.at(-1)).toContain('--full')

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'flow-stack', surface, ...PANE } as any)
    expect(await ui.find({ type: 'Text', text: /S2 token bucket · doing/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'FAIL' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'merge PR #3' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /search · wt-search · flow-stack-ab \(idle\)/ })).toBeDefined()
    if (surface === 'terminal') {
      await ui.press({ key: 'approve-2' })
      expect(runs.find(a => a[1] === 'gate')?.slice(1)).toEqual(['gate', '2', 'approve', 'merge PR #3'])
      expect(said[0]).toBe('The human approved gate 2 in the /flow-pane; see GATES.md and DECISIONS.tsv.')
      await ui.press({ key: 'reject-2' })
      expect(said[1]).toContain('rejected gate 2')
    }
    await ui.unmount()
  }
})

test('bar fills in eighths of a cell and clamps', () => {
  expect(bar(0, 4)).toBe('░░░░')
  expect(bar(0.5, 4)).toBe('██░░')
  expect(bar(1 / 32, 4)).toBe('▏░░░')
  expect(bar(2, 4)).toBe('████')
})

test('the open pane animates: spinner turns, progress bar eases in, gates pulse', async ($, hooks) => {
  const on = hooks as any
  const clock = mock.clock(on)
  on('fs.read', async () => ({ value: PROFILE }))
  on('process.run', async (_$: unknown, e: { argv: readonly string[] }) => ({
    value: { exitCode: 0, stdout: JSON.stringify(e.argv.includes('--full') ? FULL : STATUS), stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
  }))
  on('env.get', async () => ({ value: '/home/me' }))
  on('session.cwd', async () => ({ value: '/tmp' }))
  on('session.start', async (_$: unknown, e: unknown) => e)
  on('command.register', async () => ({ value: undefined }))
  on('ui.open', async () => ({ value: { id: 'flow-pane' } }))
  let redraws = 0
  on('ui.invalidate', async () => {
    redraws++
    return { value: undefined }
  })
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })
  await ($ as any).command.run({ command: 'flow-pane' })

  const ui = await $.ui.mount({ plugin: 'flow-stack', surface: 'terminal', ...PANE } as any)
  expect(await ui.find({ type: 'Text', text: bar(0, 24) })).toBeDefined()
  await ui.unmount()

  // frame 1: the header shows spin(1), the active slice S2 (row 1) spin(2)
  await clock.advance(100)
  const turned = await $.ui.mount({ plugin: 'flow-stack', surface: 'terminal', ...PANE } as any)
  expect(await turned.find({ type: 'Text', text: spin(2) })).toBeDefined()
  expect(await turned.find({ type: 'Text', text: /^◆ GATES/ })).toBeDefined()
  await turned.unmount()

  await clock.advance(3500)
  const settled = await $.ui.mount({ plugin: 'flow-stack', surface: 'terminal', ...PANE } as any)
  expect(await settled.find({ type: 'Text', text: bar(1 / 3, 24) })).toBeDefined()
  // frame 36: the gates line is in its dim half of the pulse; frame 1 was in its lit half
  expect(await settled.find({ type: 'Text', text: /^◇ GATES · 1 waiting on you/ })).toBeDefined()
  await settled.unmount()
  expect(redraws).toBeGreaterThan(30)
})

test('strip groups consecutive verdicts', () => {
  expect(strip(['FAIL', 'FAIL', 'PASS', 'FAIL'])).toEqual([
    { verdict: 'FAIL', cells: '■■' },
    { verdict: 'PASS', cells: '■' },
    { verdict: 'FAIL', cells: '■' },
  ])
})

test('the pane shows each subagent live, the evidence strip, and context and cost gauges', async ($, hooks) => {
  const on = hooks as any
  const clock = mock.clock(on)
  const full = { ...FULL, runs: ['FAIL', 'PASS', 'PASS'], est_usd: 4 }
  on('fs.read', async () => ({ value: PROFILE }))
  on('process.run', async (_$: unknown, e: { argv: readonly string[] }) => ({
    value: { exitCode: 0, stdout: JSON.stringify(e.argv.includes('--full') ? full : STATUS), stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
  }))
  on('env.get', async () => ({ value: '/home/me' }))
  on('session.cwd', async () => ({ value: '/tmp' }))
  on('session.start', async (_$: unknown, e: unknown) => e)
  on('command.register', async () => ({ value: undefined }))
  on('ui.open', async () => ({ value: { id: 'flow-pane' } }))
  on('ui.invalidate', async () => ({ value: undefined }))
  on('session.usage', async () => ({ value: { startedAt: 0, context: { window: 200000, percent: 72 }, rateLimits: [], cost: { usd: 1 } } }))
  on('agent.spawn', async (_$: unknown, e: { model?: string }) => ({ model: e.model ?? 'inherit', agentId: 'a1' }))
  on('tool.call', async () => ({ result: { type: 'text', text: '' } }))
  on('turn.complete', async (_$: unknown, e: unknown) => e)
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })
  await ($ as any).command.run({ command: 'flow-pane' })

  await ($ as any).agent.spawn({ prompt: 'review it', description: 'Review the diff', subagentType: 'flow-stack:reviewer' })
  await ($ as any).tool.call({ tool: 'Read', input: { file_path: '/tmp/x' }, agentId: 'a1' })
  await ($ as any).tool.call({ tool: 'Read', input: { file_path: '/tmp/y' }, agentId: 'a1' })
  await clock.advance(3000)

  const live = await $.ui.mount({ plugin: 'flow-stack', surface: 'terminal', ...PANE } as any)
  expect(await live.find({ type: 'Text', text: /AGENTS · 1 running/ })).toBeDefined()
  expect(await live.find({ type: 'Text', text: /^reviewer\s+opus\s+Review the diff {2}3s · 2 tools$/ })).toBeDefined()
  expect(await live.find({ type: 'Text', text: '■' })).toBeDefined()
  expect(await live.find({ type: 'Text', text: '■■' })).toBeDefined()
  expect(await live.find({ type: 'Text', text: 'last 3 checks · 2 pass' })).toBeDefined()
  expect(await live.find({ type: 'Text', text: 'context 72%' })).toBeDefined()
  expect(await live.find({ type: 'Text', text: '$1.00 this session · task est $4.00' })).toBeDefined()
  await live.unmount()

  await ($ as any).turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 't', agentId: 'a1', reason: 'answer', text: 'ok', category: null, explanation: null })
  await clock.advance(200)
  const ended = await $.ui.mount({ plugin: 'flow-stack', surface: 'terminal', ...PANE } as any)
  expect(await ended.find({ type: 'Text', text: /AGENTS · 0 running/ })).toBeDefined()
  // one ✓ for the done slice S1, one for the agent
  expect(await ended.findAll({ type: 'Text', text: '✓' })).toHaveLength(2)
  await ended.unmount()

  await clock.advance(9000)
  const gone = await $.ui.mount({ plugin: 'flow-stack', surface: 'terminal', ...PANE } as any)
  expect(await gone.find({ type: 'Text', text: /AGENTS/ })).toBeUndefined()
  await gone.unmount()
})
