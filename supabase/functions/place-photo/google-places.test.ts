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

Deno.test("selectGooglePlace rejects a nearby venue that only shares a generic name token", () => {
  const selected = selectGooglePlace(
    [place("Sunset Coffee", 34.0777, -118.2588)],
    input,
  );
  if (selected !== null) throw new Error("accepted generic-only name overlap");
});

Deno.test("selectGooglePlace accepts a nearby renamed venue when its distinctive name and address agree", () => {
  const selected = selectGooglePlace(
    [{
      id: "google-saba",
      displayName: { text: "Saba Coffee Shop" },
      formattedAddress: "12912 Venice Blvd., Los Angeles, CA 90066, USA",
      location: { latitude: 33.9993338, longitude: -118.4414794 },
      photos: [{
        name: "places/saba/photos/representative",
        widthPx: 1_600,
        heightPx: 1_200,
      }],
    }],
    {
      name: "Saba Cafe and Surf",
      address: "12912 Venice Blvd., Los Angeles, CA 90066",
      latitude: 33.9993338,
      longitude: -118.4414794,
      sourceProvider: "mapkit",
      sourceProviderPlaceID: "mapkit-saba",
    },
  );
  if (selected?.id !== "google-saba") {
    throw new Error(`selected ${selected?.id ?? "nothing"}`);
  }
});

Deno.test("selectGooglePlace accepts a renamed venue at the same coordinate when no address is stored", () => {
  const selected = selectGooglePlace(
    [{
      id: "google-saba-no-address",
      displayName: { text: "Saba Coffee Shop" },
      formattedAddress: "12912 Venice Blvd., Los Angeles, CA 90066, USA",
      location: { latitude: 33.9993338, longitude: -118.4414794 },
      photos: [{
        name: "places/saba/photos/representative",
        widthPx: 1_600,
        heightPx: 1_200,
      }],
    }],
    {
      name: "Saba Cafe and Surf",
      address: null,
      latitude: 33.9993338,
      longitude: -118.4414794,
      sourceProvider: "mapkit",
      sourceProviderPlaceID: "mapkit-saba",
    },
  );
  if (selected?.id !== "google-saba-no-address") {
    throw new Error(`selected ${selected?.id ?? "nothing"}`);
  }
});

Deno.test("representativePhoto uses the first usable photo returned by the provider", () => {
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
