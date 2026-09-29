'use client'

import { type ReactNode, useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import styles from './landing.module.css'
import { AMBER } from './icons'
import { type AppLanguageCode, type Localizer, localizer } from './languages'
import { GET_IT } from './sections'
import { SERVERS, DEMO_GROUPS, portColor } from './servers'

// A working copy of the WhatThePort popover. Scrolling picks the view for each
// section; clicking around works like the real app until the next section.

type View = { name: 'list' } | { name: 'detail'; port: string } | { name: 'cleanUp' }

const SECTION_VIEWS: View[] = [
  { name: 'list' },
  { name: 'detail', port: '3000' },
  { name: 'detail', port: '6006' },
  { name: 'cleanUp' },
  { name: 'list' },
  { name: 'list' },
  { name: 'list' },
]

// The last section shows the dot matrix. Every other section opens the popover.
const opensPopover = (section: number) => section !== GET_IT

const suggested = (running: string[]) =>
  SERVERS.filter((s) => s.cleanUp?.suggested && running.includes(s.port)).map((s) => s.port)

export function useDemo(section: number) {
  const [running, setRunning] = useState(() => SERVERS.map((s) => s.port))
  const [view, setView] = useState<View>(SECTION_VIEWS[section])
  const [direction, setDirection] = useState(1)
  const [open, setOpen] = useState(opensPopover(section))
  const [selected, setSelected] = useState(() => suggested(SERVERS.map((s) => s.port)))
  const previous = useRef(section)

  useEffect(() => {
    if (previous.current === section) return
    setDirection(section > previous.current ? 1 : -1)
    previous.current = section
    setView(SECTION_VIEWS[section])
    setOpen(opensPopover(section))
    setSelected(suggested(running))
    // `running` intentionally omitted: stopping a server shouldn't reset the view.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [section])

  const go = useCallback(
    (next: View, dir: number) => {
      setDirection(dir)
      if (next.name === 'cleanUp') setSelected(suggested(running))
      setView(next)
    },
    [running],
  )

  const stop = useCallback((ports: string[]) => {
    setRunning((current) => current.filter((port) => !ports.includes(port)))
    setSelected((current) => current.filter((port) => !ports.includes(port)))
    setDirection(-1)
    setView((current) => {
      if (current.name === 'detail' && ports.includes(current.port)) {
        return { name: 'list' }
      }
      return current
    })
  }, [])

  const restartAll = useCallback(() => {
    const all = SERVERS.map((s) => s.port)
    setRunning(all)
    setSelected(suggested(all))
  }, [])

  const toggleSelected = useCallback((port: string) => {
    setSelected((current) => (current.includes(port) ? current.filter((p) => p !== port) : [...current, port]))
  }, [])

  // A detail view for a server that's been stopped falls back to the list.
  const shown: View = view.name === 'detail' && !running.includes(view.port) ? { name: 'list' } : view

  return {
    running: SERVERS.filter((s) => running.includes(s.port)),
    view: shown,
    direction,
    open,
    setOpen,
    selected,
    toggleSelected,
    go,
    stop,
    restartAll,
  }
}

export type Demo = ReturnType<typeof useDemo>

// Keeps the popover's height animating between views, the way a macOS popover resizes.
function Frame({ children, viewKey }: { children: ReactNode; viewKey: string }) {
  const innerRef = useRef<HTMLDivElement>(null)
  const [height, setHeight] = useState<number>()

  useLayoutEffect(() => {
    const inner = innerRef.current
    if (!inner) return
    const measure = () => setHeight(inner.offsetHeight)
    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(inner)
    return () => observer.disconnect()
  }, [viewKey])

  return (
    <div className={styles.popover} style={{ height }}>
      <div ref={innerRef}>{children}</div>
    </div>
  )
}

// `language` shows the app's own translations, laid out right-to-left for Hebrew.
export function AppPopover({
  demo,
  language = 'en',
  focusBoard = false,
}: {
  demo: Demo
  language?: AppLanguageCode
  focusBoard?: boolean
}) {
  const { view, direction } = demo
  const l = localizer(language)
  const key =
    view.name === 'detail'
      ? `detail-${view.port}`
      : demo.running.length
        ? view.name === 'cleanUp'
          ? 'list'
          : view.name
        : 'empty'

  const content = <BoardOnly l={l} focusBoard={focusBoard} />

  return (
    <Frame viewKey={key}>
      <div
        key={key}
        className={styles.view}
        style={{ ['--dir' as string]: direction }}
        lang={language}
        dir={l.rtl ? 'rtl' : 'ltr'}
      >
        {content}
      </div>
    </Frame>
  )
}

// Brief confirmation on buttons that would open something outside the demo.
function useFlash() {
  const [flash, setFlash] = useState<string | null>(null)
  const timer = useRef<ReturnType<typeof setTimeout>>()
  useEffect(() => () => clearTimeout(timer.current), [])
  const trigger = useCallback((id: string) => {
    setFlash(id)
    clearTimeout(timer.current)
    timer.current = setTimeout(() => setFlash(null), 1400)
  }, [])
  return [flash, trigger] as const
}

function BoardOnly({ l, focusBoard = false }: { l: Localizer; focusBoard?: boolean }) {
  const [flash, trigger] = useFlash()
  const boardRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const node = boardRef.current
    if (!focusBoard || !node) return
    const scroller = node.closest(`.${styles.popover}`)
    if (!(scroller instanceof HTMLElement)) return
    const top = node.getBoundingClientRect().top - scroller.getBoundingClientRect().top + scroller.scrollTop
    scroller.scrollTop = top
  }, [focusBoard])

  return (
    <div className={`${styles.popSection} ${styles.rowList}`}>
      <div className={styles.boardTabs} role="tablist" ref={boardRef}>
        {['Overview', 'All', 'Local', 'LAN', 'Stopped', 'System'].map((tab) => (
          <span key={tab} className={tab === 'Overview' ? styles.boardTabOn : styles.boardTab} role="tab">
            {l.text(tab)}
          </span>
        ))}
      </div>
      {DEMO_GROUPS.map((group) => (
        <div key={group.title}>
          <div className={styles.groupLabel}>{l.text(group.title)}</div>
          {group.rows.map((row) => (
            <div key={row.id} className={styles.serverRow} data-interactive>
              <span className={styles.portLabel}>
                <span className={styles.rowPort} style={{ color: row.port ? portColor(row.port) : '#EBEBF566' }}>
                  {row.port || '—'}
                </span>
              </span>
              <span className={styles.rowMain}>
                <span className={styles.rowName}>{row.name}</span>
                <span className={styles.rowSub}>
                  <span className={styles.ellipsis} style={{ color: row.detail === 'Firmware only' || row.detail === 'Stopped' ? AMBER : undefined }}>
                    {l.text(row.detail)}
                  </span>
                </span>
                <span className={styles.cardActions}>
                  {row.detail === 'Stopped' ? (
                    <button type="button" className={styles.cardAction} onClick={(e) => e.stopPropagation()}>{l.text('Start')}</button>
                  ) : row.detail === 'Firmware only' ? null : (
                    <button type="button" className={styles.cardAction} onClick={(e) => { e.stopPropagation(); trigger(row.id) }}>{flash === row.id ? l.text('Opened') : l.text('Open')}</button>
                  )}
                  {row.id === 'dialdash' && (
                    <>
                      <button type="button" className={styles.cardAction} onClick={(e) => e.stopPropagation()}>{l.text('Restart')}</button>
                      <button type="button" className={styles.cardAction} onClick={(e) => e.stopPropagation()}>{l.text('Kill')}</button>
                    </>
                  )}
                </span>
              </span>
            </div>
          ))}
        </div>
      ))}
    </div>
  )
}
