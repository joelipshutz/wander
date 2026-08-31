const maximumCaptionLength = 30_000;

const handleExpression =
  /(^|[^A-Za-z0-9._@])@([A-Za-z0-9_](?:[A-Za-z0-9_]|\.(?=[A-Za-z0-9_])){0,29})(?![A-Za-z0-9_]|\.(?:\.|[A-Za-z0-9_]))/gu;

export type CaptionStructuralRole =
  | "primary_list_item"
  | "honorable_mention"
  | "credit"
  | "partner"
  | "unstructured";

export type CaptionListMarker = "numbered" | "ranked" | "bulleted";

type CaptionMentionBase = {
  sourceOrder: number;
  characterIndex: number;
  lineIndex: number;
  structuralRole: CaptionStructuralRole;
  isPrimary: boolean;
};

export type CaptionHandleMention = CaptionMentionBase & {
  kind: "handle";
  sourceMention: string;
  username: string;
};

export type CaptionListItem = CaptionMentionBase & {
  kind: "list_item";
  marker: CaptionListMarker;
  ordinal: number | null;
  text: string;
};

export type CaptionMention = CaptionHandleMention | CaptionListItem;

export type InstagramCaptionInventory = {
  mentions: CaptionMention[];
  handleMentions: CaptionHandleMention[];
  listItems: CaptionListItem[];
  profileUsernames: string[];
};

type PendingMention =
  | (Omit<CaptionHandleMention, "sourceOrder"> & { tieBreak: number })
  | (Omit<CaptionListItem, "sourceOrder"> & { tieBreak: number });

type ParsedListItem = {
  marker: CaptionListMarker;
  ordinal: number | null;
  text: string;
  markerOffset: number;
};

type SectionHeading = {
  role: Exclude<CaptionStructuralRole, "primary_list_item" | "unstructured">;
  isHeadingOnly: boolean;
};

/**
 * Builds a bounded, deterministic inventory from untrusted Instagram caption
 * text. This function only recognizes source structure; it never interprets or
 * executes instructions contained in the caption.
 */
export function inventoryInstagramCaption(
  value: unknown,
): InstagramCaptionInventory {
  const caption = boundedCaption(value);
  if (!caption) return emptyInventory();

  const pending: PendingMention[] = [];
  const profileUsernames: string[] = [];
  const profileUsernameSet = new Set<string>();
  let activeSectionRole: CaptionStructuralRole | null = null;
  let lineOffset = 0;

  for (const [lineIndex, line] of caption.split("\n").entries()) {
    const leadingWhitespace = line.length - line.trimStart().length;
    const trimmed = line.trim();
    const listItem = parseListItem(trimmed);
    const structuralText = listItem?.text ?? trimmed;
    const negativeHeading = sectionHeading(structuralText);
    const positiveHeading = isPrimarySectionHeading(structuralText);

    if (negativeHeading) activeSectionRole = negativeHeading.role;
    else if (positiveHeading) activeSectionRole = "primary_list_item";

    const directNegativeRole = directNegativeRoleForLine(structuralText);
    const listRole = directNegativeRole ??
      (isNegativeRole(activeSectionRole) ? activeSectionRole : null) ??
      "primary_list_item";
    const isStructuralHeading = Boolean(
      (negativeHeading?.isHeadingOnly ?? false) || positiveHeading,
    );

    if (listItem && !isStructuralHeading) {
      pending.push({
        kind: "list_item",
        characterIndex: lineOffset + leadingWhitespace + listItem.markerOffset,
        lineIndex,
        structuralRole: listRole,
        isPrimary: listRole === "primary_list_item",
        marker: listItem.marker,
        ordinal: listItem.ordinal,
        text: listItem.text,
        tieBreak: 0,
      });
    }

    const handleRole = directNegativeRole ??
      (isNegativeRole(activeSectionRole) ? activeSectionRole : null) ??
      (listItem && !isStructuralHeading ? "primary_list_item" : "unstructured");
    for (const match of line.matchAll(handleExpression)) {
      if (match.index === undefined) continue;
      const sourceMention = `@${match[2]}`;
      const username = match[2].toLocaleLowerCase("en-US");
      pending.push({
        kind: "handle",
        characterIndex: lineOffset + match.index + match[1].length,
        lineIndex,
        structuralRole: handleRole,
        isPrimary: handleRole === "primary_list_item",
        sourceMention,
        username,
        tieBreak: 1,
      });
      if (!profileUsernameSet.has(username)) {
        profileUsernameSet.add(username);
        profileUsernames.push(username);
      }
    }

    lineOffset += line.length + 1;
  }

  const mentions = pending
    .sort((left, right) =>
      left.characterIndex - right.characterIndex ||
      left.tieBreak - right.tieBreak
    )
    .map(({ tieBreak: _tieBreak, ...mention }, sourceOrder) => ({
      ...mention,
      sourceOrder,
    })) as CaptionMention[];
  const handleMentions = mentions.filter(isHandleMention);
  const listItems = mentions.filter(isListItem);
  return { mentions, handleMentions, listItems, profileUsernames };
}

function boundedCaption(value: unknown): string {
  if (typeof value !== "string") return "";
  return value
    .slice(0, maximumCaptionLength)
    .replace(/\r\n?/gu, "\n")
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/gu, " ");
}

function emptyInventory(): InstagramCaptionInventory {
  return {
    mentions: [],
    handleMentions: [],
    listItems: [],
    profileUsernames: [],
  };
}

function parseListItem(value: string): ParsedListItem | null {
  const keycap = value.match(/^\s*(\d{1,3})\uFE0F?\u20E3\s*(\S.*)$/u);
  if (keycap) {
    return {
      marker: "ranked",
      ordinal: Number(keycap[1]),
      text: keycap[2].trim(),
      markerOffset: value.indexOf(keycap[1]),
    };
  }

  const ranked = value.match(
    /^\s*(?:(?:no\.?|number|rank)\s*#?\s*|#)(\d{1,3})(?:\s*[.):\-–—])?\s+(\S.*)$/iu,
  );
  if (ranked) {
    return {
      marker: "ranked",
      ordinal: Number(ranked[1]),
      text: ranked[2].trim(),
      markerOffset: value.indexOf(ranked[1]),
    };
  }

  const numbered = value.match(
    /^\s*(?:(?:no\.?|number|rank)\s*)?(\d{1,3})(?:[.):]|\s*[-–—])\s+(\S.*)$/iu,
  );
  if (numbered) {
    return {
      marker: "numbered",
      ordinal: Number(numbered[1]),
      text: numbered[2].trim(),
      markerOffset: value.indexOf(numbered[1]),
    };
  }

  const bullet = value.match(/^\s*([*•●▪◦‣⁃·\-–—]|📍)\s+(\S.*)$/u);
  if (!bullet) return null;
  return {
    marker: "bulleted",
    ordinal: null,
    text: bullet[2].trim(),
    markerOffset: value.indexOf(bullet[1]),
  };
}

function sectionHeading(value: string): SectionHeading | null {
  const honorable = value.match(
    /^\s*((?:(?:hon\.?|honou?rable)\s+mentions?)(?:\s+only)?|also\s+consider|also\s+try|other\s+mentions?)\s*(?:(?:[:\-–—])\s*(.*))?$/iu,
  );
  if (honorable) {
    return {
      role: "honorable_mention",
      isHeadingOnly: !(honorable[2]?.trim()),
    };
  }

  const credit = value.match(
    /^\s*((?:photo|video|music|content|creator)?\s*credits?|special\s+thanks)\s*(?:(?:[:\-–—])\s*(.*))?$/iu,
  );
  if (credit) {
    return { role: "credit", isHeadingOnly: !(credit[2]?.trim()) };
  }

  const partner = value.match(
    /^\s*((?:brand\s+)?partners?|sponsors?|sponsored)\s*(?:(?:[:\-–—])\s*(.*))?$/iu,
  );
  if (partner) {
    return { role: "partner", isHeadingOnly: !(partner[2]?.trim()) };
  }
  return null;
}

function isPrimarySectionHeading(value: string): boolean {
  return /^\s*(?:(?:the|our|my)\s+)?(?:(?:top(?:\s+\d{1,3})?|best|favorites?|favourites?)(?:\s+[\p{L}\p{N}&'’.-]+){0,5}\s+(?:places?|destinations?|restaurants?|caf(?:e|é)s?|coffee\s+shops?|bars?|hotels?|shops?|spots?|stops?|things\s+to\s+do)|main\s+list|rankings?|top(?:\s+\d{1,3})?|best|favorites?|favourites?|places?|destinations?|restaurants?|caf(?:e|é)s?|coffee\s+shops?|bars?|hotels?|shops?|spots?|stops?|things\s+to\s+do|where\s+to\s+(?:eat|drink|stay|shop))\s*[:\-–—]?\s*$/iu
    .test(value);
}

function directNegativeRoleForLine(
  value: string,
): Exclude<CaptionStructuralRole, "primary_list_item" | "unstructured"> | null {
  if (
    /^\s*(?:(?:hon\.?|honou?rable)\s+mentions?|also\s+consider|also\s+try)\b/iu
      .test(
        value,
      )
  ) return "honorable_mention";
  if (
    /^\s*(?:(?:photo|video|filmed|shot|created|posted)\s+by|credits?\s*(?:to|by|:)|special\s+thanks\s+to|courtesy\s+of)\b/iu
      .test(value)
  ) return "credit";
  if (
    /^\s*(?:in\s+partnership\s+with|paid\s+partnership\s+with|partner(?:ed)?\s+with|sponsored\s+by|partners?\s*:|sponsors?\s*:)/iu
      .test(value)
  ) return "partner";
  return null;
}

function isNegativeRole(
  value: CaptionStructuralRole | null,
): value is Exclude<
  CaptionStructuralRole,
  "primary_list_item" | "unstructured"
> {
  return value === "honorable_mention" || value === "credit" ||
    value === "partner";
}

function isHandleMention(
  mention: CaptionMention,
): mention is CaptionHandleMention {
  return mention.kind === "handle";
}

function isListItem(mention: CaptionMention): mention is CaptionListItem {
  return mention.kind === "list_item";
}
