import { createRouter, createWebHistory } from 'vue-router';

import AppShell from './layouts/AppShell.vue';
import ClusterListView from './views/ClusterListView.vue';
import ClusterWorkspaceView from './views/ClusterWorkspaceView.vue';
import InstallConfirmView from './views/InstallConfirmView.vue';
import JobExecutionView from './views/JobExecutionView.vue';

const STAGE_PATTERN = 'cluster-info|nodes|settings|precheck';

export const routes = [
  {
    path: '/',
    component: AppShell,
    children: [
      {
        path: '',
        name: 'cluster-list',
        component: ClusterListView
      },
      {
        path: 'clusters/:clusterId',
        redirect: (to) => ({
          name: 'cluster-workspace',
          params: { clusterId: to.params.clusterId, stage: 'cluster-info' }
        })
      },
      {
        path: `clusters/:clusterId/:stage(${STAGE_PATTERN})`,
        name: 'cluster-workspace',
        component: ClusterWorkspaceView
      },
      {
        path: 'clusters/:clusterId/install',
        redirect: (to) => ({ name: 'install-confirm', params: { clusterId: to.params.clusterId } })
      },
      {
        path: 'clusters/:clusterId/install/confirm',
        name: 'install-confirm',
        component: InstallConfirmView
      },
      {
        path: 'jobs/:jobId/execution',
        name: 'job-execution',
        component: JobExecutionView
      }
    ]
  },
  {
    path: '/:pathMatch(.*)*',
    redirect: '/'
  }
];

export function createAppRouter(history = createWebHistory(import.meta.env.BASE_URL)) {
  return createRouter({
    history,
    routes
  });
}

export default createAppRouter();
