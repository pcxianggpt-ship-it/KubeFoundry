import { describe, expect, it } from 'vitest';
import { groupDeploymentUnits, summarizeDeploymentUnit } from './deploymentUnits';

describe('部署单元汇总', () => {
  it('按固定元数据分组和排序，并保持组内步骤顺序', () => {
    const units = groupDeploymentUnits([
      { id: 3, name: '挂载 NFS 工作节点', order: 18, stage_key: 'nfs', stage_name: '部署 NFS 组件', stage_order: 6, step_order_in_stage: 3 },
      { id: 1, name: '安装 NFS Provisioner', order: 17, stage_key: 'nfs', stage_name: '部署 NFS 组件', stage_order: 6, step_order_in_stage: 2 },
      { id: 2, name: '安装镜像仓库', order: 8, stage_key: 'registry', stage_name: '部署镜像仓库', stage_order: 2, step_order_in_stage: 1 }
    ]);

    expect(units.map((unit) => unit.key)).toEqual(['registry', 'nfs']);
    expect(units[1].steps.map((step) => step.id)).toEqual([1, 3]);
  });

  it('按失败、执行中、等待、验证跳过和依赖阻塞规则汇总状态', () => {
    expect(summarizeDeploymentUnit([{ status: 'success' }, { status: 'failed' }]).status).toBe('failed');
    expect(summarizeDeploymentUnit([{ status: 'success' }, { status: 'running' }]).status).toBe('running');
    expect(summarizeDeploymentUnit([{ status: 'success' }, { status: 'pending' }]).status).toBe('pending');
    expect(summarizeDeploymentUnit([
      { status: 'skipped', status_reason: 'PREVERIFY_SATISFIED' },
      { status: 'skipped', status_reason: 'PREVERIFY_SATISFIED' }
    ])).toMatchObject({ status: 'verified', label: '已验证并跳过' });
    expect(summarizeDeploymentUnit([
      { status: 'skipped', status_reason: 'JOB_ABORTED' },
      { status: 'skipped', status_reason: 'COMPONENT_GROUP_PREVIOUS_STEP_FAILED' }
    ])).toMatchObject({ status: 'blocked', label: '已阻塞' });
    expect(summarizeDeploymentUnit([
      { status: 'success' },
      { status: 'skipped', status_reason: 'PREVERIFY_SATISFIED' }
    ])).toMatchObject({ status: 'success', preverified: 1 });
  });
});
