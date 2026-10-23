"""Share embedded raster payloads within a standalone SVG, preserving instances."""
import xml.etree.ElementTree as ET

SVG = 'http://www.w3.org/2000/svg'
ET.register_namespace('', SVG)

def deduplicate_images(svg):
    root = ET.fromstring(svg)
    instances = list(root.iter(f'{{{SVG}}}image'))
    parents = {child: parent for parent in root.iter() for child in parent}
    existing_ids = {node.get('id') for node in root.iter() if node.get('id')}
    shared = {}
    definitions = ET.Element(f'{{{SVG}}}defs')
    for instance in instances:
        href = instance.get('href')
        if not href or not href.startswith('data:image/'):
            continue
        key = (href, instance.get('width'), instance.get('height'))
        if key not in shared:
            index = len(shared) + 1
            name = f'embedded-photo-{index}'
            while name in existing_ids:
                index += 1
                name = f'embedded-photo-{index}'
            existing_ids.add(name)
            shared[key] = name
            attrs = {'id': name, 'href': href}
            for attr in ['width', 'height']:
                if instance.get(attr) is not None:
                    attrs[attr] = instance.get(attr)
            ET.SubElement(definitions, f'{{{SVG}}}image', attrs)
        attrs = {k: v for k, v in instance.attrib.items() if k not in ['href', 'width', 'height']}
        attrs['href'] = '#' + shared[key]
        replacement = ET.Element(f'{{{SVG}}}use', attrs)
        replacement.text = instance.text
        replacement.tail = instance.tail
        for child in list(instance):
            replacement.append(child)
        parent = parents[instance]
        index = list(parent).index(instance)
        parent.remove(instance)
        parent.insert(index, replacement)
    if len(definitions):
        root.insert(0, definitions)
    return ET.tostring(root, encoding='unicode')
