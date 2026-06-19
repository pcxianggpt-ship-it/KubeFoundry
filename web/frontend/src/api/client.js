const JSON_HEADERS = {
  'Content-Type': 'application/json'
};

async function request(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {
      ...(options.body ? JSON_HEADERS : {}),
      ...(options.headers || {})
    }
  });

  const text = await response.text();
  let payload = null;
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch (error) {
      payload = text;
    }
  }

  if (!response.ok) {
    const message = payload && payload.message ? payload.message : `请求失败：${response.status}`;
    throw new Error(message);
  }

  return payload;
}

export function listClusters() {
  return request('/api/clusters');
}

export function getCluster(clusterId) {
  return request(`/api/clusters/${clusterId}`);
}

export function createCluster(data) {
  return request('/api/clusters', {
    method: 'POST',
    body: JSON.stringify(data)
  });
}

export function updateCluster(clusterId, data) {
  return request(`/api/clusters/${clusterId}`, {
    method: 'PUT',
    body: JSON.stringify(data)
  });
}

export function listNodes(clusterId) {
  return request(`/api/clusters/${clusterId}/nodes`);
}

export function createNode(clusterId, data) {
  return request(`/api/clusters/${clusterId}/nodes`, {
    method: 'POST',
    body: JSON.stringify(data)
  });
}

export function updateNode(nodeId, data) {
  return request(`/api/nodes/${nodeId}`, {
    method: 'PUT',
    body: JSON.stringify(data)
  });
}

export function deleteNode(nodeId) {
  return request(`/api/nodes/${nodeId}`, {
    method: 'DELETE'
  });
}

export function upsertSshCredentials(clusterId, data) {
  return request(`/api/clusters/${clusterId}/ssh-credentials`, {
    method: 'PUT',
    body: JSON.stringify(data)
  });
}

export function getSettings() {
  return request('/api/settings');
}

export function updateSettings(data) {
  return request('/api/settings', {
    method: 'PUT',
    body: JSON.stringify(data)
  });
}

export function getClusterSettings(clusterId) {
  return request(`/api/clusters/${clusterId}/settings`);
}

export function updateClusterSettings(clusterId, data) {
  return request(`/api/clusters/${clusterId}/settings`, {
    method: 'PUT',
    body: JSON.stringify(data)
  });
}

export function startPrecheck(clusterId) {
  return request(`/api/clusters/${clusterId}/precheck`, {
    method: 'POST'
  });
}

export function startInstall(clusterId) {
  return request(`/api/clusters/${clusterId}/install`, {
    method: 'POST'
  });
}

export function getJob(jobId) {
  return request(`/api/jobs/${jobId}`);
}

export function getJobSteps(jobId) {
  return request(`/api/jobs/${jobId}/steps`);
}

export function getJobLogs(jobId) {
  return request(`/api/jobs/${jobId}/logs`);
}

export function getJobConfigYaml(jobId) {
  return request(`/api/jobs/${jobId}/config-yaml`);
}
