# REC-343 app icon candidates

The revised original warm-map direction is the selected production icon. The Liquid Glass version remains here as the comparison candidate from the review.

`source/recme-warm-map-original-source-1254.png` is a byte-for-byte copy of the initially supplied image. `source/recme-warm-map-selected-source-1254.png` is the selected revision with the explicitly marked palm at x=7.8%, y=11.5% removed and the surrounding peach rooftop reconstructed. The selected candidate's Icon Composer source is a 1024 px normalization of that revision.

## Variants

- `RecmeWarmMapOriginal.icon` contains the selected warm-map revision with a sparse, irregular palm row. Icon Composer specular, blur, translucency, and shadow effects are disabled.
- `RecmeWarmMapLiquidGlass.icon` uses a high-fidelity generated restyle of the same map composition, then applies restrained Icon Composer material settings: specular on, 12% blur, 6% translucency, and 8% neutral shadow.

Each `.icon` document contains its opaque 1024 px source; the `previews` folder contains 180 px and 87 px legibility checks. Ryan approved the original direction for production on 2026-08-20, and its source now owns `Wander/Resources/AppIcon.icon` plus the generated asset-catalog renditions.

## Selected palm revision prompt

Built-in image editing was used with the original supplied image as the edit target:

> Edit only the palm trees running down the diagonal sage-green strip along the left side. Reduce them from the current dense, evenly spaced row to approximately eight palms. Arrange those palms with intentionally irregular natural spacing, varied gaps, subtle differences in height and crown size, and slight varied leans so they do not look copied or symmetrical. Preserve absolutely everything else in appearance. Every edited palm, including its full trunk, leaves, and shadow, must remain completely within the diagonal sage-green strip.

The final coordinate-based edit removed only the palm centered at x=7.8%, y=11.5% from the supplied marked image and preserved every other palm.

## Liquid Glass image-generation prompt

Built-in image editing was used with the supplied image as the edit target:

> Transform the supplied square rec.me map artwork into a restrained matte Liquid Glass version. Preserve the exact full-frame square composition, camera angle, crop, map geometry, coastline, park, buildings, trees, red pin placement, and centered wordmark placement. Use Apple-inspired frosted liquid glass with subtle dimensional refraction, fine edge highlights, soft translucent depth, and gentle cool-blue undertones; premium but matte, never glossy. Preserve the warm cream map, sage park, blue water, vivid red-orange pin, and black serif wordmark. Keep the lowercase text exactly legible as `rec.me` with no spelling, font, punctuation, scale, or alignment change. Do not add or remove objects. Do not bake a rounded-corner mask into the image. Maintain an opaque square background suitable for a 1024 × 1024 app icon. Avoid neon, chrome, metallic, rainbow/prismatic effects, excessive shine, bloom, dark-mode restyling, new symbols, new labels, extra pins, cropping, reframing, or warped text.

## Validation

- Both `.icon` documents open successfully in Apple Icon Composer.
- Both source PNGs are square, opaque, and 1024 × 1024.
- The `rec.me` wordmark and red map pin remain identifiable at 180 px and 87 px.
