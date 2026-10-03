import { describe, expect, it } from 'vitest';
import { generate } from '../src/generate.js';
import { normalize } from '../src/normalize.js';
import { validate } from '../src/validate.js';
import { assetCatalog, scenario, sheets } from './helpers.js';

describe('per-line voice assets', () => {
  it.each(['daily', 'middle_event'])(
    'exports optional voice and catalog filename for %s',
    (type) => {
      const { data, issues } = normalize(
        sheets({
          scenarios: [scenario({ scenario_type: type, voice_asset_id: 'voice_test' })],
          assets: [
            assetCatalog({ asset_id: 'voice_test', asset_type: 'voice', file_name: 'clip.mp3' }),
          ],
        }),
      );
      expect(issues.errors).toEqual([]);
      expect(validate(data).issues.errors).toEqual([]);
      expect(generate(data).scenarios[0]!.nodes[0]).toMatchObject({
        voiceAssetId: 'voice_test',
        voiceFileName: 'clip.mp3',
      });
    },
  );

  it.each([
    [undefined, 'dangling_asset_id'],
    [assetCatalog({ asset_id: 'voice_test', asset_type: 'se' }), 'asset_type_mismatch'],
    [
      assetCatalog({ asset_id: 'voice_test', asset_type: 'voice', enabled: false }),
      'disabled_asset_reference',
    ],
  ])('rejects unavailable or wrong-type voice references', (asset, code) => {
    const { data } = normalize(
      sheets({
        scenarios: [scenario({ voice_asset_id: 'voice_test' })],
        assets: asset ? [asset] : [],
      }),
    );
    expect(validate(data).issues.errors).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          code,
          at: expect.objectContaining({ column: 'voice_asset_id' }),
        }),
      ]),
    );
  });

  it('keeps old silent rows compatible', () => {
    const { data } = normalize(sheets({ scenarios: [scenario()] }));
    const node = generate(data).scenarios[0]!.nodes[0]!;
    expect(node.voiceAssetId).toBeUndefined();
    expect(node.voiceFileName).toBeUndefined();
  });
});
