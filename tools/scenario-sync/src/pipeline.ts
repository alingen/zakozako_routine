import type { RawSheets } from './types.js';
import { normalize } from './normalize.js';
import { validate } from './validate.js';
import {
  generate,
  serialize,
  planWrite,
  type WritePlan,
  type GeneratedArtifacts,
} from './generate.js';
import { diff, type DiffReport } from './diff.js';
import { IssueBag } from './issues.js';
import { DAILY_OUTPUT, EVENTS_OUTPUT } from './config.js';

export interface PipelineResult {
  issues: IssueBag;
  artifacts: GeneratedArtifacts | null;
  plans: WritePlan[];
  diff: DiffReport | null;
}

/**
 * Pure core: raw sheets -> validated + generated artifacts + write plan + diff.
 * No file writes, no network, no process exits. Everything the CLI and the
 * tests share lives here.
 */
export function runPipeline(raw: RawSheets): PipelineResult {
  const issues = new IssueBag();

  const { data, issues: normIssues } = normalize(raw);
  issues.merge(normIssues);

  const { issues: valIssues } = validate(data);
  issues.merge(valIssues);

  if (issues.hasErrors) {
    return { issues, artifacts: null, plans: [], diff: null };
  }

  const artifacts = generate(data);
  const plans = [
    planWrite(DAILY_OUTPUT, serialize(artifacts.daily)),
    planWrite(EVENTS_OUTPUT, serialize(artifacts.events)),
  ];
  const diffReport = diff(DAILY_OUTPUT, EVENTS_OUTPUT, artifacts);

  return { issues, artifacts, plans, diff: diffReport };
}
