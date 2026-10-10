// The board and decide popups. Board: every Claude pane, needs-you first; the selected one's slices,
// gates and evidence below. Decide: one gate's options (recommended first), a note, then the answer.
import { Box, Text, useApp, useInput } from 'ink'
import React, { useEffect, useState } from 'react'
import { type Gate, type Row, options, tier } from './model'

export type Io = {
  load: () => Row[]
  decide: (row: Row, n: number, question: string, verdict: 'approve' | 'reject', choice: string, note: string) => string
  focus: (pane: string) => void
  watch: (panes: string[], onChange: () => void) => () => void
}

const stateMark: Record<Row['state'], string> = { working: '◎', blocked: '◐', done: '✓', idle: '○', unknown: '·' }
const verdictColor = (v: string) => (v === 'PASS' ? 'green' : v === 'FAIL' ? 'red' : 'gray')

export function Board({ io }: { io: Io }) {
  const { exit } = useApp()
  const [list, setList] = useState<Row[]>(() => io.load())
  const [sel, setSel] = useState(0)
  const [deciding, setDeciding] = useState<{ row: Row; gate: Gate } | null>(null)
  const [msg, setMsg] = useState('')
  const panes = list.map(r => r.pane).join(' ')
  useEffect(() => io.watch(panes.split(' ').filter(Boolean), () => setList(io.load())), [panes])

  const row = list[Math.min(sel, list.length - 1)]
  useInput((input, key) => {
    if (deciding) return
    if (input === 'q' || key.escape) exit()
    else if (key.downArrow || input === 'j') setSel(i => Math.min(i + 1, list.length - 1))
    else if (key.upArrow || input === 'k') setSel(i => Math.max(i - 1, 0))
    else if (input === 'r') setList(io.load())
    else if (key.return && row) {
      io.focus(row.pane)
      exit()
    } else if (input === 'd' && row?.task?.gates?.length) setDeciding({ row, gate: row.task.gates[0]! })
  })

  if (deciding) {
    return (
      <Decide io={io} row={deciding.row} gate={deciding.gate}
        onDone={m => { setMsg(m); setDeciding(null); setList(io.load()) }} />
    )
  }
  const gates = list.reduce((n, r) => n + (r.task?.gates?.length ?? 0), 0)
  return (
    <Box flexDirection="column" paddingX={1}>
      <Box justifyContent="space-between">
        <Text bold>flow board <Text color="gray">· {list.length} pane(s){gates ? '' : ' · nothing needs you'}</Text>
          {gates ? <Text color="yellow"> · ⚑ {gates} gate(s)</Text> : null}</Text>
        <Text color="gray">↑↓ select · ↵ jump · d decide · r reload · q close</Text>
      </Box>
      <Box flexDirection="column" marginTop={1}>
        {list.length === 0 && <Text color="gray">No Claude panes in herdr.</Text>}
        {list.map((r, i) => <Line key={r.pane} row={r} on={i === sel} />)}
      </Box>
      {row?.task && <Detail row={row} />}
      {msg && <Box marginTop={1}><Text color="cyan">{msg}</Text></Box>}
    </Box>
  )
}

function Line({ row, on }: { row: Row; on: boolean }) {
  const t = row.task
  const g = t?.gates?.length ?? 0
  return (
    <Box>
      <Text color={on ? 'cyan' : undefined}>{on ? '▸ ' : '  '}</Text>
      <Box width={4}><Text color="yellow">{g ? `⚑${g}` : ''}</Text></Box>
      <Box width={24}><Text bold={!!t} color={t ? undefined : 'gray'} wrap="truncate">{t?.task ?? '(no task)'}</Text></Box>
      <Box width={30}>
        <Text wrap="truncate">{t ? `${t.slice?.id ?? '—'} ${t.slice?.title ?? ''}` : ''}</Text>
      </Box>
      <Box width={7}><Text color="gray">{t ? `${t.done}/${t.total}` : ''}</Text></Box>
      <Box width={6}>
        <Text color={verdictColor(t?.evidence?.verdict ?? '')}>{t?.evidence ? (t.stale ? '~' : '') + t.evidence.verdict : ''}</Text>
      </Box>
      <Text color="gray" wrap="truncate">{stateMark[row.state]} {row.session} · {row.pane}</Text>
    </Box>
  )
}

function Detail({ row }: { row: Row }) {
  const t = row.task!
  return (
    <Box flexDirection="column" marginTop={1} borderStyle="round" borderColor="gray" paddingX={1}>
      <Text bold>{t.task} <Text color="gray">· {row.cwd}</Text></Text>
      {(t.slices ?? []).map(s => (
        <Text key={s.id} color={s.status === 'doing' ? 'cyan' : undefined}>
          <Text color={verdictColor(s.verdict)}>{tier(s)}</Text> {s.id} {s.title} <Text color="gray">{s.status}</Text>
        </Text>
      ))}
      {(t.gates ?? []).map(g => (
        <Text key={g.n} color="yellow" wrap="truncate">⚑ {g.n}. {g.question} <Text color="gray">{g.detail}</Text></Text>
      ))}
      {!!t.runs?.length && (
        <Text>
          <Text color="gray">runs </Text>
          {t.runs.slice(-30).map((v, i) => <Text key={i} color={verdictColor(v)}>{v === 'PASS' ? '●' : '○'}</Text>)}
        </Text>
      )}
      <Text color="gray">◆ verified · ◇ reported done · ✗ failing · ~ evidence older than the last edit</Text>
    </Box>
  )
}

type Choice = { label: string; verdict: 'approve' | 'reject'; choice: string }

export function Decide({ io, row, gate, onDone }: { io: Io; row: Row; gate: Gate; onDone: (msg: string) => void }) {
  const { options: opts, recommend } = options(gate)
  const choices: Choice[] = [
    ...(opts.length ? opts.map(o => ({ label: o.label, verdict: 'approve' as const, choice: o.label })) : [{ label: 'Approve', verdict: 'approve' as const, choice: '' }]),
    { label: 'Reject', verdict: 'reject', choice: '' },
  ]
  const start = Math.max(0, opts.findIndex(o => o.key === recommend))
  const [sel, setSel] = useState(start)
  const [note, setNote] = useState('')
  const [typing, setTyping] = useState(false)

  useInput((input, key) => {
    if (typing) {
      if (key.return || key.escape) setTyping(false)
      else if (key.backspace || key.delete) setNote(n => n.slice(0, -1))
      else if (input && !key.ctrl && !key.meta) setNote(n => (n + input).slice(0, 300))
      return
    }
    if (key.escape || input === 'q') onDone('')
    else if (key.downArrow || input === 'j') setSel(i => Math.min(i + 1, choices.length - 1))
    else if (key.upArrow || input === 'k') setSel(i => Math.max(i - 1, 0))
    else if (input === 'n') setTyping(true)
    else if (key.return) {
      const c = choices[sel]!
      onDone(io.decide(row, gate.n, gate.question, c.verdict, c.choice, note))
    }
  })

  const evidence = gate.detail.split(' · ').filter(l => !l.startsWith('options:'))
  return (
    <Box flexDirection="column" paddingX={1} borderStyle="round" borderColor="yellow">
      <Text bold color="yellow">⚑ {row.task?.task} · gate {gate.n}</Text>
      <Text bold>{gate.question}</Text>
      {evidence.map((l, i) => <Text key={i} color="gray" wrap="truncate">{l}</Text>)}
      <Box flexDirection="column" marginTop={1}>
        {choices.map((c, i) => (
          <Text key={c.label} color={i === sel ? 'cyan' : c.verdict === 'reject' ? 'red' : undefined}>
            {i === sel ? '▸ ' : '  '}{c.label}{opts[i]?.key === recommend ? <Text color="green"> (recommended)</Text> : null}
          </Text>
        ))}
      </Box>
      <Box marginTop={1}>
        <Text color="gray">note: </Text>
        <Text color={typing ? 'cyan' : undefined}>{note || (typing ? '' : '—')}{typing ? '▌' : ''}</Text>
      </Box>
      <Text color="gray">{typing ? '↵ done typing' : '↑↓ choose · n note · ↵ answer · esc cancel'} · {row.session} is told to read GATES.md</Text>
    </Box>
  )
}

// DecideFocused: the decide popup on a key, for the focused pane's oldest open gate.
export function DecideFocused({ io, pane }: { io: Io; pane: string }) {
  const { exit } = useApp()
  const [done, setDone] = useState('')
  const row = io.load().find(r => r.pane === pane)
  const gate = row?.task?.gates?.[0]
  useInput((_, key) => { if (!gate || done) exit() })
  if (done) return <Text color="cyan">{done} · any key closes</Text>
  if (!row || !gate) return <Text color="gray">No open gate on this pane{row?.task ? ` (${row.task.task})` : ''}. Any key closes.</Text>
  return <Decide io={io} row={row} gate={gate} onDone={m => (m ? setDone(m) : exit())} />
}
