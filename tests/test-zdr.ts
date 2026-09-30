/**
 * Locks the ZDR header policy to Command Code's model naming conventions and to
 * the free models that carry no marker in their id.
 *
 * Contributor and free models are offered in exchange for data usage, so they
 * must never receive the `x-cmd-zdr: 1` header.
 */

import assert from "node:assert/strict"
import { describe, it } from "node:test"

import { MODEL_COSTS } from "../src/pricing.ts"
import { isZdrExcludedModel, zdrHeadersForModel } from "../src/zdr.ts"

const ZDR_HEADERS = { "x-cmd-zdr": "1" }

const EXCLUDED_MODEL_IDS = [
  // Contributor models.
  "meta/muse-spark-1.2-contributor",
  "meta/muse-spark-1.3-contributor",
  // Free models with a name marker.
  "inclusionai/ling-3.0-flash-sante:free",
  "inclusionai/ling-3.1-flash:free",
  "poolside/laguna-s-2.1-free",
  // Free model without a name marker (see the "Free models" section of pricing).
  "stealth/space-bunny-alpha",
]

const INCLUDED_MODEL_IDS = [
  "deepseek/deepseek-v4-pro",
  "deepseek/deepseek-v4.1-flash",
  "gpt-5.6-luna",
  "meta/muse-spark-1.3",
  "poolside/laguna-s-2.1",
]

const FREE_PRICED_MODEL_IDS = Object.entries(MODEL_COSTS)
  .filter(
    ([, cost]) =>
      cost.input === 0 && cost.output === 0 && cost.cacheRead === 0 && cost.cacheWrite === 0,
  )
  .map(([modelId]) => modelId)

describe("ZDR model policy", () => {
  it("excludes contributor and free models", () => {
    for (const modelId of EXCLUDED_MODEL_IDS) {
      assert.equal(isZdrExcludedModel(modelId), true, `${modelId} must be excluded from ZDR`)
      assert.equal(
        zdrHeadersForModel(modelId, ZDR_HEADERS),
        undefined,
        `${modelId} must not send ZDR headers`,
      )
    }
  })

  it("keeps the ZDR header for paid models", () => {
    for (const modelId of INCLUDED_MODEL_IDS) {
      assert.equal(isZdrExcludedModel(modelId), false, `${modelId} must stay eligible for ZDR`)
      assert.deepEqual(zdrHeadersForModel(modelId, ZDR_HEADERS), ZDR_HEADERS)
    }
  })

  it("returns no headers when ZDR is disabled", () => {
    assert.equal(zdrHeadersForModel("gpt-5.6-luna", undefined), undefined)
  })

  it("excludes every zero-priced model from the pricing table", () => {
    assert.ok(FREE_PRICED_MODEL_IDS.length > 0)
    for (const modelId of FREE_PRICED_MODEL_IDS) {
      assert.equal(
        isZdrExcludedModel(modelId),
        true,
        `${modelId} is free-priced and must be excluded from ZDR`,
      )
    }
  })
})
