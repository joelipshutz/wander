# REC-343 app icon candidates

These candidates preserve the current production icon while the new warm-map direction is reviewed.

`source/recme-warm-map-original-source-1254.png` is a byte-for-byte copy of the supplied image. The original Icon Composer variant uses a 1024 px normalization of that source without visual restyling.

## Variants

- `RecmeWarmMapOriginal.icon` keeps the supplied artwork unchanged apart from deterministic resizing to an opaque 1024 × 1024 source. Icon Composer specular, blur, translucency, and shadow effects are disabled.
- `RecmeWarmMapLiquidGlass.icon` uses a high-fidelity generated restyle of the same map composition, then applies restrained Icon Composer material settings: specular on, 12% blur, 6% translucency, and 8% neutral shadow.

Each `.icon` document contains its opaque 1024 px source; the `previews` folder contains 180 px and 87 px legibility checks. Neither candidate replaces `Wander/Resources/AppIcon.icon` or the production asset catalog.

## Liquid Glass image-generation prompt

Built-in image editing was used with the supplied image as the edit target:

> Transform the supplied square rec.me map artwork into a restrained matte Liquid Glass version. Preserve the exact full-frame square composition, camera angle, crop, map geometry, coastline, park, buildings, trees, red pin placement, and centered wordmark placement. Use Apple-inspired frosted liquid glass with subtle dimensional refraction, fine edge highlights, soft translucent depth, and gentle cool-blue undertones; premium but matte, never glossy. Preserve the warm cream map, sage park, blue water, vivid red-orange pin, and black serif wordmark. Keep the lowercase text exactly legible as `rec.me` with no spelling, font, punctuation, scale, or alignment change. Do not add or remove objects. Do not bake a rounded-corner mask into the image. Maintain an opaque square background suitable for a 1024 × 1024 app icon. Avoid neon, chrome, metallic, rainbow/prismatic effects, excessive shine, bloom, dark-mode restyling, new symbols, new labels, extra pins, cropping, reframing, or warped text.

## Validation

- Both `.icon` documents open successfully in Apple Icon Composer.
- Both source PNGs are square, opaque, and 1024 × 1024.
- The `rec.me` wordmark and red map pin remain identifiable at 180 px and 87 px.
