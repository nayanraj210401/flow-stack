// Entry for the plugin's popups: `main.tsx board` or `main.tsx decide`.
import { render } from 'ink'
import React from 'react'
import { decide, focus, load, watch } from './herdr'
import { Board, DecideFocused } from './ui'

const io = { load, decide, focus, watch }
// a popup has no HERDR_PANE_ID; the pane it opened over is in the invocation context
const ctx = JSON.parse(process.env.HERDR_PLUGIN_CONTEXT_JSON || '{}') as { focused_pane_id?: string }
const pane = process.env.FLOW_PANE || ctx.focused_pane_id || ''

const app = process.argv[2] === 'decide' ? <DecideFocused io={io} pane={pane} /> : <Board io={io} />
await render(app).waitUntilExit()
process.exit(0)
