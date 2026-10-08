import typography from '@tailwindcss/typography';

/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  darkMode: 'class',
  theme: {
    extend: {
      fontFamily: {
        // Inter for reading; Outfit only where a heading asks for it.
        sans: ['Inter', 'system-ui', 'sans-serif'],
        display: ['Outfit', 'Inter', 'system-ui', 'sans-serif'],
      },
      fontSize: {
        // The UI leans on text-xs for body copy; 12px was too small to read comfortably.
        xs: ['0.8125rem', { lineHeight: '1.15rem' }],
      },
      colors: {
        brand: {
          50: '#eef2ff',
          100: '#e0e7ff',
          200: '#c7d2fe',
          300: '#a5b4fc',
          400: '#818cf8',
          500: '#6366f1',
          600: '#4f46e5',
          700: '#4338ca',
          800: '#3730a3',
          900: '#312e81',
        },
        // ── Canonical semantic palette (use these, not one-off hues) ──
        // success → emerald | warning → amber | danger → rose | info → sky
        // brand   → indigo  | assignments follow brand (indigo), NOT purple
      },
    },
  },
  plugins: [
    typography,
  ],
}
