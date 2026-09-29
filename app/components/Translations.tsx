'use client'

import { useId, useState } from 'react'
import Image from 'next/image'
import styles from './landing.module.css'
import { APP_LANGUAGES } from './languages'

// Real native screenshots: the control previews a language without changing
// visitor preferences or pretending to run macOS onboarding in the browser.
export function Translations({ desktop = false, visible = true }: { desktop?: boolean; visible?: boolean }) {
  const [code, setCode] = useState('ja')
  const id = useId()
  const language = APP_LANGUAGES.find((item) => item.code === code) ?? APP_LANGUAGES[0]

  return (
    <figure className={`${styles.translations} ${desktop ? styles.translationsDesktop : ''}`} hidden={!visible}>
      <figcaption>
        <label htmlFor={id}>Preview app language</label>
        <select id={id} value={code} onChange={(event) => setCode(event.target.value)}>
          {APP_LANGUAGES.map((item) => <option key={item.code} value={item.code} lang={item.code}>{item.label}</option>)}
        </select>
      </figcaption>
      <Image
        src={`/languages/onboarding-${language.code}.png`}
        alt={`WhatThePort’s first onboarding step in ${language.name}, with a Language picker and Get started button`}
        width={960}
        height={1304}
        sizes="(max-width: 900px) 340px, 400px"
      />
    </figure>
  )
}
