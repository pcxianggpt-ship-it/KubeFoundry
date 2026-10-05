import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

describe('安装确认页响应式布局', () => {
  it.each(['classic', 'apple'])('%s 版桌面端对齐四项节点信息，窄屏改为单列且不隐藏 IPv4', theme => {
    const styles = readFileSync(`src/themes/${theme}.css`, 'utf8');
    expect(styles).toContain('grid-template-columns: minmax(140px, 1.2fr) minmax(120px, 0.8fr) minmax(110px, 1fr) auto;');
    expect(styles).toContain('.confirm-node-ip');

    const mobileStyles = styles.split('@media (max-width: 520px)')[1]
      .split('@media (prefers-reduced-motion: reduce)')[0];
    expect(mobileStyles).toContain('.confirm-node-list li,');
    expect(mobileStyles).toContain('grid-template-columns: 1fr;');
    expect(mobileStyles).not.toContain('display: none');
  });
});
