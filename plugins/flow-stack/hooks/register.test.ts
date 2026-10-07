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
  expect(bandText({ ...STATUS, stale: true })).toContain('S2:red FAIL · edited since')
})

// Starts a session whose profile is PROFILE and whose status.sh prints `status`.
async function start($: any, on: any, status: object = {}, profile = PROFILE) {
  on('fs.read', async () => ({ value: profile }))
  on('process.run', async () => ({ value: { exitCode: 0, stdout: JSON.stringify(status), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('env.get', async () => ({ value: '/home/me' }))
  on('session.cwd', async () => ({ value: '/tmp' }))
  on('session.start', async (_$: unknown, e: unknown) => e)
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
