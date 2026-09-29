'use client'

import { useEffect, useRef, useState } from 'react'
import styles from './landing.module.css'

const HEADLINES = [
  { language: 'en', text: 'Your language.' },
  { language: 'ja', text: 'あなたの言語。' },
  { language: 'de', text: 'Deine Sprache.' },
  { language: 'uk', text: 'Ваша мова.' },
  { language: 'fr', text: 'Votre langue.' },
  { language: 'zh-Hans', text: '你的语言。' },
  { language: 'he', text: 'השפה שלך.' },
  { language: 'es', text: 'Tu idioma.' },
]

export function LanguageHeadline() {
  const ref = useRef<HTMLHeadingElement>(null)
  const [index, setIndex] = useState(0)

  useEffect(() => {
    const element = ref.current
    if (!element) return
    const motion = window.matchMedia('(prefers-reduced-motion: reduce)')
    let visible = false
    let timer: ReturnType<typeof setInterval> | undefined
    const update = () => {
      clearInterval(timer)
      if (visible && !document.hidden && !motion.matches) {
        timer = setInterval(() => setIndex((value) => (value + 1) % HEADLINES.length), 2800)
      }
    }
    const observer = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting
      update()
    }, { threshold: 0.5 })
    observer.observe(element)
    document.addEventListener('visibilitychange', update)
    motion.addEventListener('change', update)
    return () => {
      clearInterval(timer)
      observer.disconnect()
      document.removeEventListener('visibilitychange', update)
      motion.removeEventListener('change', update)
    }
  }, [])

  const headline = HEADLINES[index]
  return (
    <h2 ref={ref} className={`${styles.headline} ${styles.languageHeadline}`} aria-label="Your language.">
      <span key={headline.language} lang={headline.language} dir="auto" aria-hidden="true">{headline.text}</span>
    </h2>
  )
}
