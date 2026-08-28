import type { CellRef } from './types.js';

export type Severity = 'error' | 'warning';

export interface Issue {
  severity: Severity;
  /** Machine-friendly code, e.g. `duplicate_node_id`. */
  code: string;
  message: string;
  /** Where the problem is, when it maps to a cell. */
  at?: CellRef;
  /** The offending value, if short and safe to print. */
  value?: string;
  /** Concrete suggestion for the sheet editor. */
  fix?: string;
}

export class IssueBag {
  readonly issues: Issue[] = [];

  add(issue: Issue): void {
    this.issues.push(issue);
  }

  error(code: string, message: string, extra: Partial<Issue> = {}): void {
    this.add({ severity: 'error', code, message, ...extra });
  }

  warning(code: string, message: string, extra: Partial<Issue> = {}): void {
    this.add({ severity: 'warning', code, message, ...extra });
  }

  get errors(): Issue[] {
    return this.issues.filter((i) => i.severity === 'error');
  }

  get warnings(): Issue[] {
    return this.issues.filter((i) => i.severity === 'warning');
  }

  get hasErrors(): boolean {
    return this.errors.length > 0;
  }

  merge(other: IssueBag): void {
    this.issues.push(...other.issues);
  }
}

export function formatIssue(issue: Issue): string {
  const loc = issue.at
    ? `[${issue.at.sheet}!行${issue.at.row}${issue.at.column ? ` / 列 ${issue.at.column}` : ''}]`
    : '[全体]';
  const value =
    issue.value !== undefined && issue.value !== '' ? ` (値: "${truncate(issue.value)}")` : '';
  const fix = issue.fix ? `\n     → 修正案: ${issue.fix}` : '';
  return `${loc} ${issue.message}${value}${fix}`;
}

export function truncate(s: string, max = 80): string {
  return s.length > max ? `${s.slice(0, max)}…` : s;
}
