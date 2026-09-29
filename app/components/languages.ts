// Keep these stable codes aligned with InterfaceLanguage in Localization.swift.
export const APP_LANGUAGES = [
  { code: 'en', label: 'English', name: 'English' },
  { code: 'de', label: 'Deutsch', name: 'German' },
  { code: 'fr', label: 'Français', name: 'French' },
  { code: 'es', label: 'Español', name: 'Spanish' },
  { code: 'zh-Hans', label: '简体中文', name: 'Simplified Chinese' },
  { code: 'he', label: 'עברית', name: 'Hebrew' },
  { code: 'ja', label: '日本語', name: 'Japanese' },
  { code: 'uk', label: 'Українська', name: 'Ukrainian' },
] as const

export type AppLanguageCode = 'system' | (typeof APP_LANGUAGES)[number]['code']
export const appLanguageLabel = (code: AppLanguageCode) =>
  APP_LANGUAGES.find((language) => language.code === code)?.label ?? 'System default'
