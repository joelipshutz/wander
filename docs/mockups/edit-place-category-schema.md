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
│ source                                 edited │
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

subcategory
┌─────────────────────────────────────────────┐
│ [Restaurant] [Thai restaurant] [Fast food restaurant]
│ [Sushi restaurant] [Pizza restaurant] [Ramen restaurant]
│
│ [ custom subcategory                    ] [+]
└─────────────────────────────────────────────┘
```

## Data Meaning

```text
Shared place category metadata
  primary_category: filterable shared taxonomy id, like restaurant.
  subcategory: provider or AI subtype, like Thai restaurant.
  category_source: provider, deterministic, ai, legacy, or unknown.
  category_confidence: 0 to 1 confidence when known.
  raw_provider_type: original Google/Apple/provider type, like thai restaurant.

Smart-question answers
  structured answers chosen from category-driven prompts.
  Example: occasion = ["date night", "group"]

Personal labels
  user-owned memory/filter tags.
  Example: personal_labels = ["spicy", "joe rec", "birthday"]

Personal category override
  user_places.category_override stores a user-edited primary category.
  user_places.subcategory_override stores a suggested or custom user subcategory.
  The shared places row keeps provider/AI/legacy metadata, so one user's edit does
  not rewrite the canonical category for everyone.
```

## Filter Contract

```text
Filters use the effective primary category:
  user_places.category_override ?? places.primary_category ?? places.category

Provider subcategories never need to match filters directly:
  "thai restaurant" -> restaurant
  "4-star hotel" -> hotel
  "art supply store" -> shop
  "train station" -> transportation
```
