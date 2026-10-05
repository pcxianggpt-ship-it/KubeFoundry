import { readonly, ref } from 'vue';

export const THEME_STORAGE_KEY = 'kubefoundry.ui-theme';
export const DEFAULT_THEME = 'apple';
export const THEME_OPTIONS = Object.freeze([
  { value: 'classic', label: '经典版' },
  { value: 'apple', label: 'Apple 版' }
]);

const selectedTheme = ref(DEFAULT_THEME);
export const theme = readonly(selectedTheme);

function applyTheme(value) {
  selectedTheme.value = value;
  document.documentElement.dataset.kfTheme = value;
}

// 在挂载前恢复外观，避免刷新时先显示另一版；禁用存储时仍可正常切换。
export function initializeTheme() {
  let stored;
  try {
    stored = window.localStorage.getItem(THEME_STORAGE_KEY);
  } catch { /* 浏览器隐私设置可能禁用本地存储。 */ }
  applyTheme(THEME_OPTIONS.some(option => option.value === stored) ? stored : DEFAULT_THEME);
}

export function setTheme(value) {
  if (!THEME_OPTIONS.some(option => option.value === value)) return;
  applyTheme(value);
  try {
    window.localStorage.setItem(THEME_STORAGE_KEY, value);
  } catch { /* 外观已经生效，本次会话继续使用所选版本。 */ }
}
