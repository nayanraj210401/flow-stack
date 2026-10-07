import { expect, test } from 'claude-code/testing'

import { bandText, parseBudget } from './register'

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
  expect(parseBudget(PROFILE)).toEqual({ subagent_model: 'haiku', build_model: 'sonnet', design_model: 'opus' })
})

test('bandText shows task, slice, progress, tdd phase, and evidence freshness', () => {
  expect(bandText(STATUS)).toBe('flow · rate-limit · S2 token bucket · 1/3 slices · tdd red · S2:red FAIL')
  expect(bandText({ ...STATUS, stale: true })).toContain('S2:red FAIL · edited since')
})

// Starts a session whose profile is PROFILE and whose status.sh prints `status`.
async function start($: any, on: any, status: object = {}) {
  on('fs.read', async () => ({ value: PROFILE }))
  on('process.run', async () => ({ value: { exitCode: 0, stdout: JSON.stringify(status), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('env.get', async () => ({ value: '/home/me' }))
  on('session.cwd', async () => ({ value: '/tmp' }))
  on('session.start', async (_$: unknown, e: unknown) => e)
  await $.session.start({ cwd: '/tmp', surface: null, isInteractive: false })
}

async function spawnWith($: any, on: any, args: { subagentType: string; model?: string }) {
  let model: string | undefined
  on('agent.spawn', async (_$: unknown, e: { model?: string }) => {
    model = e.model
    return { model: e.model ?? 'inherit' }
  })
  await start($, on)
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

for (const type of ['general-purpose', 'Explore']) {
  test(`agent.spawn leaves ${type} alone`, async ($, on) => {
    expect(await spawnWith($, on, { subagentType: type })).toBe(undefined)
  })
}

const BAND = { component: 'AbovePrompt', props: { hasSurvey: false, isWorking: false, maxRows: 4, bodyColumns: 100 } } as const

test('the band shows the active task on every surface', async ($, on) => {
  await start($, on, STATUS)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'flow-stack', surface, ...BAND } as any)
    expect(await ui.find({ type: 'Text', text: /flow · rate-limit · S2 token bucket/ })).toBeDefined()
    await ui.unmount()
  }
})
