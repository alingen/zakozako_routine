export type IssueSeverity = 'error' | 'warning';

export interface CellRef {
  sheet: string;
  /** One-based row number as shown in Google Sheets. */
  row: number;
  column: string;
}

export interface Issue {
  severity: IssueSeverity;
  code: string;
  message: string;
  at?: CellRef;
  value?: string;
  fix?: string;
}

type IssueDetails = Omit<Issue, 'severity' | 'code' | 'message'>;

export class IssueBag {
  readonly errors: Issue[] = [];
  readonly warnings: Issue[] = [];

  get hasErrors(): boolean {
    return this.errors.length > 0;
  }

  error(code: string, message: string, details: IssueDetails = {}): void {
    this.errors.push({ severity: 'error', code, message, ...details });
  }

  warning(code: string, message: string, details: IssueDetails = {}): void {
    this.warnings.push({ severity: 'warning', code, message, ...details });
  }

  merge(other: IssueBag): void {
    this.errors.push(...other.errors);
    this.warnings.push(...other.warnings);
  }
}

export function formatIssue(issue: Issue): string {
  const location = issue.at
    ? `${issue.at.sheet}!${issue.at.column}${issue.at.row}`
    : 'location unknown';
  const value = issue.value === undefined ? '' : ` value=${JSON.stringify(issue.value)}`;
  const fix = issue.fix ? ` / fix: ${issue.fix}` : '';
  return `[${issue.code}] ${location}: ${issue.message}${value}${fix}`;
}
