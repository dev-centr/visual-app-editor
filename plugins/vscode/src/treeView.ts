import * as vscode from 'vscode';
import { label, type TreeNode } from './model';
import type { ServiceManager } from './service';

export class WidgetTreeProvider implements vscode.TreeDataProvider<TreeNode> {
  private readonly emitter = new vscode.EventEmitter<TreeNode | undefined | void>();
  readonly onDidChangeTreeData = this.emitter.event;

  constructor(private readonly svc: ServiceManager) {
    svc.onDidChange(() => this.emitter.fire());
  }

  getTreeItem(n: TreeNode): vscode.TreeItem {
    const it = new vscode.TreeItem(label(n), n.children.length ? vscode.TreeItemCollapsibleState.Expanded : vscode.TreeItemCollapsibleState.None);
    it.id = `${this.svc.state.rel}#${this.svc.state.page}#${n.path.join('.')}`;
    it.contextValue = n === this.svc.state.root ? 'root' : 'child';
    it.tooltip = n.args.map((a) => (a.name ? `${a.name}: ${a.source}` : a.source)).join('\n') || n.type;
    it.command = { command: 'visualAppEditor.select', title: 'Select', arguments: [n] };
    return it;
  }

  getChildren(n?: TreeNode): TreeNode[] {
    if (!n) return this.svc.state.root ? [this.svc.state.root] : [];
    return n.children;
  }

  getParent(n: TreeNode): TreeNode | undefined {
    const find = (p: TreeNode): TreeNode | undefined => {
      for (const c of p.children) {
        if (c === n) return p;
        const f = find(c);
        if (f) return f;
      }
      return undefined;
    };
    return this.svc.state.root && n !== this.svc.state.root ? find(this.svc.state.root) : undefined;
  }
}
