import Anthropic from "@anthropic-ai/sdk";
import { ProviderError, type VisionProvider, type VisionRequest, type VisionResponse } from "./types";

export const DEFAULT_ANTHROPIC_MODEL = "claude-opus-5";

/**
 * Claude vision provider.
 *
 * - Structured output (`output_config.format`) constrains the reply to the criteria schema.
 * - `effort: "low"`: this is a classification task, so extra thinking adds latency/cost for
 *   little benefit.
 * - Server-side refusal fallbacks (`fallbacks: "default"`): if a safety classifier declines,
 *   the API re-runs the request on Anthropic's recommended fallback model instead of failing.
 */
export class AnthropicVisionProvider implements VisionProvider {
  readonly name = "anthropic";

  constructor(
    private readonly client: Anthropic,
    readonly model: string = DEFAULT_ANTHROPIC_MODEL,
    private readonly timeoutMs = 60_000,
  ) {}

  async assess(request: VisionRequest): Promise<VisionResponse> {
    let response: Anthropic.Beta.BetaMessage;
    try {
      response = await this.client.beta.messages.create(
        {
          model: this.model,
          max_tokens: 4096,
          betas: ["server-side-fallback-2026-07-01"],
          fallbacks: "default",
          output_config: {
            effort: "low",
            format: { type: "json_schema", schema: request.schema },
          },
          system: request.system,
          messages: [
            {
              role: "user",
              content: [
                {
                  type: "image",
                  source: { type: "base64", media_type: request.mediaType, data: request.image.toString("base64") },
                },
                { type: "text", text: request.userText },
              ],
            },
          ],
        },
        { timeout: this.timeoutMs, maxRetries: 1 },
      );
    } catch (error) {
      if (error instanceof Anthropic.APIConnectionTimeoutError) {
        throw new ProviderError("timeout", "The verification service timed out.");
      }
      if (error instanceof Anthropic.RateLimitError) {
        throw new ProviderError("rate_limited", "The verification service is busy.");
      }
      if (error instanceof Anthropic.APIError) {
        throw new ProviderError("provider_error", `Verification service error (${error.status ?? "network"}).`);
      }
      throw error;
    }

    if (response.stop_reason === "refusal") {
      throw new ProviderError("refusal", "The verification service declined to assess this image.");
    }
    if (response.stop_reason === "max_tokens") {
      throw new ProviderError("provider_error", "The verification response was truncated.");
    }
    const text = response.content
      .filter((block): block is Anthropic.Beta.BetaTextBlock => block.type === "text")
      .map((block) => block.text)
      .join("");
    return { text, model: response.model };
  }
}
