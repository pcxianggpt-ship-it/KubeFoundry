import { flushPromises, mount } from '@vue/test-utils';
import ElementPlus from 'element-plus';
import { describe, expect, it } from 'vitest';

import NodeEditor from './NodeEditor.vue';

describe('NodeEditor', () => {
  it('编辑已保存密码的节点时空密码不进入请求', async () => {
    const wrapper = mount(NodeEditor, {
      props: {
        modelValue: true,
        node: {
          id: 7,
          hostname: 'worker-1',
          ip: '10.0.0.7',
          roles: ['worker'],
          ssh_user: 'root',
          ssh_port: 22,
          has_password: true
        }
      },
      global: { plugins: [ElementPlus] }
    });
    await flushPromises();

    expect(wrapper.text()).toContain('密码已保存');
    await wrapper.get('[data-testid="save-node"]').trigger('click');
    const payload = wrapper.emitted('save')[0][0];
    expect(payload).not.toHaveProperty('password');
  });
});
