# Edit Place Category Schema Mockups

Purpose: review the edit-place UX for canonical place type, smart-question answers, and personal labels without compiling the iOS app.

## Edit This Place

```text
edit this place                                      (x)
update what future you sees on the map.

┌─────────────────────────────────────────────┐
│ [fork.knife]  Jitlada                       │
│              5233 Sunset Blvd · Los Angeles │
│              Thai restaurant · Food & drink │
│              been                           │
└─────────────────────────────────────────────┘

┌─ place type ───────────────────── suggested ┐
│ category                         Food & drink ›
│ subcategory                    Thai restaurant ›
└─────────────────────────────────────────────┘

save as
[ been ] [ wanna go ]

┌─ price feel? ─────────────────────── price ┐
│ [$] [$$] [$$$]                            │
└────────────────────────────────────────────┘

┌─ best for? ───────────────────────── multi ┐
│ [quick bite] [date night] [group] [rainy night]
└────────────────────────────────────────────┘

┌─ tags ────────────────────────────── multi ┐
│ [cozy] [good table] [share plates] [worth it] [+]
└────────────────────────────────────────────┘

┌─ my labels ─────────────────────── labels ┐
│ [date night] [group] [spicy] [cozy] [worth it] [+]
└────────────────────────────────────────────┘

a note for future you
┌────────────────────────────────────────────┐
│ order the crispy rice salad; ask for heat  │
└────────────────────────────────────────────┘

stealth mode
[ toggle ]

[ update my map ]
```

## Choose Place Type

```text
choose place type                              done

[ search categories or subcategories          ]

suggested
┌─────────────────────────────────────────────┐
│ [cup]     Coffee shop        Food & drink   │
│ [fork]    Restaurant         Food & drink ✓ │
│ [glass]   Bar                Food & drink   │
│ [hike]    Hike or trail      Outdoors & nature
│ [tree]    Park               Outdoors & nature
│ [dumbbell] Gym               Health & wellness
│ [sparkles] Spiritual place   Arts, culture & faith
└─────────────────────────────────────────────┘
```

## Data Meaning

```text
Canonical place type
  category/subcategory for what the place is.

Smart-question answers
  structured answers chosen from category-driven prompts.
  Example: occasion = ["date night", "group"]

Personal labels
  user-owned memory/filter tags.
  Example: personal_labels = ["spicy", "joe rec", "birthday"]
```
