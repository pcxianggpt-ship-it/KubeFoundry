#!/bin/bash

#===============================================================================
# 脚本名称：11-setup-ssh-login.sh
# 功能：配置SSH免密登录（可选）
# 执行机器：管理节点
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: SSH免密登录配置 - 可选步骤"
echo "如需配置SSH免密登录，请手动执行以下命令："
echo "1. 在管理节点生成SSH密钥对："
echo "   ssh-keygen -t rsa -b 4096"
echo ""
echo "2. 将公钥复制到所有节点："
echo "   ssh-copy-id root@<节点IP>"
echo ""
echo "3. 验证免密登录："
echo "   ssh root@<节点IP>"
echo ""
echo "【INFO】: SSH免密登录配置说明完成"
