export const locales = ['en', 'es', 'fr', 'de', 'pt', 'ja', 'zh', 'sv'] as const;
export type Locale = (typeof locales)[number];
export const defaultLocale: Locale = 'sv';
