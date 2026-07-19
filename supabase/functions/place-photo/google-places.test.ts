import {
  type GooglePlace,
  representativePhoto,
  selectGooglePlace,
  shouldUseGooglePlaces,
} from "./google-places.ts";

const input = {
  name: "Woodcat Coffee",
  address: "1532 Sunset Blvd, Los Angeles, CA",
  latitude: 34.0777,
  longitude: -118.2588,
  sourceProvider: "mapkit",
  sourceProviderPlaceID: "mapkit-woodcat",
  requiresPhoto: true,
};

Deno.test("selectGooglePlace prefers the exact nearby venue with a photo", () => {
  const exact = place("Woodcat Coffee", 34.0777, -118.2588);
  const similar = place("Woodcat Coffee Bar", 34.0780, -118.2590);
  const selected = selectGooglePlace([similar, exact], input);
  if (selected?.id !== exact.id) {
    throw new Error(`selected ${selected?.id ?? "nothing"}`);
  }
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

Deno.test("selectGooglePlace accepts Saba's renamed listing with the stored street-only address", () => {
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
      address: "12912 Venice Blvd",
      latitude: 33.9994182,
      longitude: -118.4415397,
      sourceProvider: "mapkit",
      sourceProviderPlaceID: "mapkit-saba",
      requiresPhoto: true,
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
      requiresPhoto: true,
    },
  );
  if (selected?.id !== "google-saba-no-address") {
    throw new Error(`selected ${selected?.id ?? "nothing"}`);
  }
});

Deno.test("selectGooglePlace rejects a renamed nearby venue with a conflicting street number", () => {
  const selected = selectGooglePlace(
    [{
      id: "google-wrong-saba",
      displayName: { text: "Saba Coffee Shop" },
      formattedAddress: "12914 Venice Blvd., Los Angeles, CA 90066, USA",
      location: { latitude: 33.9994182, longitude: -118.4415397 },
      photos: [{
        name: "places/wrong-saba/photos/representative",
        widthPx: 1_600,
        heightPx: 1_200,
      }],
    }],
    {
      name: "Saba Cafe and Surf",
      address: "12912 Venice Blvd, Los Angeles, CA 90066",
      latitude: 33.9994182,
      longitude: -118.4415397,
      sourceProvider: "mapkit",
      sourceProviderPlaceID: "mapkit-saba",
      requiresPhoto: true,
    },
  );
  if (selected !== null) throw new Error("accepted conflicting street number");
});

Deno.test("representativePhoto uses the first usable photo returned by the provider", () => {
  const selected = representativePhoto({
    photos: [
      { name: "tiny", widthPx: 80, heightPx: 80 },
      { name: "storefront", widthPx: 1_600, heightPx: 1_000 },
      { name: "interior", widthPx: 1_600, heightPx: 1_000 },
    ],
  });
  if (selected?.name !== "storefront") {
    throw new Error(`selected ${selected?.name ?? "nothing"}`);
  }
});

Deno.test("shouldUseGooglePlaces rejects coordinate-backed dropped pins", () => {
  const shouldUse = shouldUseGooglePlaces({
    name: "Dropped pin",
    address: "34.09435, -118.44982",
    latitude: 34.09435,
    longitude: -118.44982,
    sourceProvider: "coordinate",
    sourceProviderPlaceID: "coordinate_34.09435_-118.44982",
    requiresPhoto: true,
  });
  if (shouldUse) throw new Error("coordinate pin would be sent to Google");
});

Deno.test("shouldUseGooglePlaces keeps MapKit venue lookups enabled", () => {
  if (!shouldUseGooglePlaces(input)) {
    throw new Error("MapKit venue lookup was disabled");
  }
});

Deno.test("selectGooglePlace can return provider metadata when a venue has no photo", () => {
  const selected = selectGooglePlace(
    [{
      id: "google-ugo",
      displayName: { text: "Ugo" },
      formattedAddress: "3865 Cardiff Ave, Culver City, CA",
      location: { latitude: 34.0223, longitude: -118.3952 },
      primaryType: "italian_restaurant",
      types: ["italian_restaurant", "restaurant", "food"],
    }],
    {
      name: "Ugo",
      address: "3865 Cardiff Ave, Culver City, CA",
      latitude: 34.0223,
      longitude: -118.3952,
      sourceProvider: "mapkit",
      sourceProviderPlaceID: "mapkit-ugo",
      requiresPhoto: false,
    },
  );
  if (selected?.primaryType !== "italian_restaurant") {
    throw new Error(`selected ${selected?.id ?? "nothing"}`);
  }
});

function place(name: string, latitude: number, longitude: number): GooglePlace {
  return {
    id: name.toLocaleLowerCase().replaceAll(" ", "-"),
    displayName: { text: name },
    formattedAddress: "1532 Sunset Blvd, Los Angeles, CA",
    location: { latitude, longitude },
    photos: [{
      name: "places/example/photos/representative",
      widthPx: 1_600,
      heightPx: 1_000,
    }],
  };
}
