import styles from './landing.module.css'
import { LanguageHeadline } from './LanguageHeadline'
import { AppleIcon, Colon, type ColonState, GitHubIcon } from './icons'
import { track } from '@vercel/analytics'
import { portColor } from './servers'
import { DOWNLOAD_URL, GITHUB_URL } from './sections'

// Marketing copy for each section. Shared by the laptop screen and the small-screen layout.

function PortLabel({ port, colon, label }: { port: string; colon: ColonState; label: string }) {
  return (
    <div className={styles.portLabel}>
      <Colon state={colon} color={portColor(port)} />
      <span className={styles.portLabelPort} style={{ color: portColor(port) }}>
        {port}
      </span>
      <span className={styles.portLabelName}>{label}</span>
    </div>
  )
}

export function Cta({ stars, location }: { stars: number | null; location: string }) {
  return (
    <div className={styles.cta}>
      <div className={styles.ctaButtons}>
        <a className={styles.download} href={DOWNLOAD_URL} download onClick={() => track('Download', { location })}>
          <AppleIcon />
          Download for macOS
        </a>
        <a className={styles.github} href={GITHUB_URL} target="_blank" rel="noopener noreferrer">
          <GitHubIcon />
          Star on GitHub
          {stars !== null && <span className={styles.githubCount}>{stars}</span>}
        </a>
      </div>
      <p className={styles.ctaMeta}>Free and open source · macOS 14 or later · No account</p>
    </div>
  )
}

const BOARD = [
  { name: 'Open', detail: 'Browser, when the card has a URL' },
  { name: 'Start', detail: 'Stopped helpers and LaunchAgents' },
  { name: 'Kill', detail: 'bootout, then the process' },
]

const FACTS = [
  { name: 'Native', detail: 'Swift, no Electron, no Dock icon.' },
  { name: 'Private', detail: 'Nothing leaves your Mac.' },
  { name: 'Shortcut', detail: '⌥⌘P', mono: true },
]

export function SectionCopy({ index, stars }: { index: number; stars: number | null }) {
  switch (index) {
    case 0:
      return (
        <div className={styles.copy}>
          <h1 className={styles.headline}>Every dev server on your Mac, in the menu bar.</h1>
          <p className={styles.body}>
            Helpers, local listeners, and devices on your LAN, on one board. A page that answers, even with a 404, has
            Open. No HTTP response is firmware-only, one card per host.
          </p>
          <Cta stars={stars} location="hero" />
        </div>
      )
    case 1:
      return (
        <div className={styles.copy}>
          <PortLabel port="80" colon="on" label="LAN" />
          <h2 className={styles.headline}>Portals on the network get Open.</h2>
          <p className={styles.body}>
            Every host advertised as HTTP, Arduino or ESPHome is probed on its port and on port 80. Any HTTP response,
            including 401, 403 and 404, is a live portal. Home Assistant, Monster Settings and the dials that serve a page
            show up as one card each.
          </p>
        </div>
      )
    case 2:
      return (
        <div className={styles.copy}>
          <PortLabel port="3232" colon="idle" label="OTA" />
          <h2 className={styles.headline}>No page means firmware only.</h2>
          <p className={styles.body}>
            bedside-dial, led-round-dial, printstatus and the other ESP32s that do not answer HTTP stay on the board
            without Open. They are one card per host, not a second row for each Bonjour type.
          </p>
        </div>
      )
    case 3:
      return (
        <div className={styles.copy}>
          <PortLabel port="8787" colon="on" label="Helpers" />
          <h2 className={styles.headline}>Start and kill stay on the card.</h2>
          <p className={styles.body}>
            Known Mac helpers that are down show Start. A running helper can be restarted or killed. The popover does not
            open a session, an editor, or a terminal.
          </p>
        </div>
      )
    case 4:
      return (
        <div className={styles.copy}>
          <PortLabel port="5177" colon="on" label="Board" />
          <h2 className={styles.headline}>Open, start and stop, on the card.</h2>
          <p className={styles.body}>
            Overview, All, Local, LAN, Stopped and System. Open, Start, Restart and Kill stay on every card you can
            control. Firmware-only devices say so, and have no Open button.
          </p>
          <ul className={styles.list}>
            {BOARD.map((row) => (
              <li key={row.name} className={styles.listRow}>
                <span className={styles.listName}>{row.name}</span>
                <span className={styles.factDetail}>{row.detail}</span>
              </li>
            ))}
          </ul>
        </div>
      )
    case 5:
      return (
        <div className={styles.copy}>
          <PortLabel port="8080" colon="on" label="Translations" />
          <LanguageHeadline />
          <p className={styles.body}>
            English, German, French, Spanish, Simplified Chinese, Hebrew, Japanese and Ukrainian.
            Choose your language in Settings. Changes apply immediately, with right-to-left layouts for Hebrew.
          </p>
          <p className={styles.body}>
            Follows your Mac’s preferred languages by default. Project names, paths and commands stay as you wrote them.
          </p>
          <a className={styles.github} href="/guides/change-app-language">About translations <span aria-hidden>↗</span></a>
        </div>
      )
    default:
      return (
        <div className={styles.copy}>
          <h2 className={styles.headline}>Know what’s running.</h2>
          <p className={styles.body}>Two white dots when everything’s fine. You’ll know when it isn’t.</p>
          <Cta stars={stars} location="get-it" />
          <ul className={styles.list}>
            {FACTS.map((fact) => (
              <li key={fact.name} className={styles.listRow} style={{ height: 44 }}>
                <span className={styles.listName} style={{ flexGrow: 0, width: 120 }}>
                  {fact.name}
                </span>
                <span className={fact.mono ? styles.listDetail : styles.factDetail}>{fact.detail}</span>
              </li>
            ))}
          </ul>
        </div>
      )
  }
}
