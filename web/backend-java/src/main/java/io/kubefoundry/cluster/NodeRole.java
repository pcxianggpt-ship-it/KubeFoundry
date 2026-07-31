package io.kubefoundry.cluster;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(name = "node_roles", uniqueConstraints = @UniqueConstraint(
        name = "uk_node_roles_node_role", columnNames = {"node_id", "role"}))
public class NodeRole {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "node_id", nullable = false)
    private Node node;

    @Column(nullable = false, length = 32)
    private String role;

    protected NodeRole() {
    }

    NodeRole(Node node, String role) {
        if (node == null) throw new IllegalArgumentException("节点不能为空");
        if (role == null || role.isBlank()) throw new IllegalArgumentException("节点角色不能为空");
        this.node = node;
        this.role = role.trim();
    }

    public Long getId() { return id; }
    public Node getNode() { return node; }
    public String getRole() { return role; }
}
