import type { AnsightHost, UiNode, UiSelector } from "./ansight-task.d.ts";

// Small phones need scrolling between the recording controls and transcript.
export async function seekVisible(
  ansight: AnsightHost,
  target: UiSelector,
  toward: "top" | "bottom",
): Promise<UiNode> {
  for (let attempt = 0; attempt <= 3; attempt++) {
    const result = await ansight.ui.find({ ...target, exact: true });
    const node = result.matches.find(candidate =>
      candidate.visible && candidate.onScreen && candidate.viewportRelation === "inside"
    );

    if (node) return node;
    if (attempt === 3) break;

    await ansight.ui.swipe({
      automationId: "harness-scroll",
      exact: true,
      direction: toward === "bottom" ? "up" : "down",
      length: 0.6,
    });
  }

  throw new Error(`Could not scroll to ${target.automationId}.`);
}
