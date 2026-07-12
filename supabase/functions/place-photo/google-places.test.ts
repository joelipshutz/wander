import {
  type GooglePlace,
  representativePhoto,
  selectGooglePlace,
} from "./google-places.ts";

const input = {
  name: "Woodcat Coffee",
  address: "1532 Sunset Blvd, Los Angeles, CA",
  latitude: 34.0777,
  longitude: -118.2588,
  sourceProvider: "mapkit",
  sourceProviderPlaceID: "mapkit-woodcat",
};

Deno.test("selectGooglePlace prefers the exact nearby venue with a photo", () => {
  const exact = place("Woodcat Coffee", 34.0777, -118.2588);
  const similar = place("Woodcat Coffee Bar", 34.0780, -118.2590);
  const selected = selectGooglePlace([similar, exact], input);
  if (selected?.id !== exact.id) throw new Error(`selected ${selected?.id ?? "nothing"}`);
});

Deno.test("selectGooglePlace rejects an unrelated result even at the same coordinate", () => {
  const selected = selectGooglePlace(
    [place("Sunset Hardware", 34.0777, -118.2588)],
    input,
  );
  if (selected !== null) throw new Error("accepted unrelated result");
});

Deno.test("representativePhoto uses the provider-ranked first usable photo", () => {
  const selected = representativePhoto({
    photos: [
      { name: "tiny", widthPx: 80, heightPx: 80 },
      { name: "storefront", widthPx: 1_600, heightPx: 1_000 },
      { name: "interior", widthPx: 1_600, heightPx: 1_000 },
    ],
  });
  if (selected?.name !== "storefront") throw new Error(`selected ${selected?.name ?? "nothing"}`);
});

function place(name: string, latitude: number, longitude: number): GooglePlace {
  return {
    id: name.toLocaleLowerCase().replaceAll(" ", "-"),
    displayName: { text: name },
    formattedAddress: "1532 Sunset Blvd, Los Angeles, CA",
    location: { latitude, longitude },
    photos: [{ name: "places/example/photos/representative", widthPx: 1_600, heightPx: 1_000 }],
  };
}
