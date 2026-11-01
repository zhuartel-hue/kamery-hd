# AriView – kontekst projektu

Aplikacja do podglądu kamer i rejestratorów (NVR/DVR) **Hikvision i Dahua**. Teraz
skupiamy się tylko na **iPhonie** (Android wyłączony w CI do czasu, gdy aplikacja będzie gotowa).
Plan i lista zadań: `docs/PLAN.md` – aktualizuj go po każdej zmianie.

## Użytkownik

- Pisze po polsku, odpowiadaj po polsku, prostym językiem (nie jest programistą).
- Ma iMaca z procesorem Intel i iPhone'a 17. Instaluje plik `AriView.ipa` przez
  **Sideloadly** z darmowym Apple ID (tryb dewelopera włączony). Darmowy certyfikat
  wygasa po 7 dniach – trzeba wtedy zainstalować ponownie.
- Testuje na prawdziwym rejestratorze Hikvision (192.168.1.50, kanały 101–401):
  podgląd i wykrywanie kamer działają. **Nagrania nie działają** („Brak nagrań”) –
  dysk rejestratora może być uszkodzony, więc testujemy kamerę z własną kartą SD.
  Czekamy na tekst z przycisku „Szczegóły techniczne” w ekranie nagrań.

## Budowanie i wydania

- Flutter 3.47 (Dart 3.13), lokalnie `/opt/flutter/bin` (może nie być w PATH).
  Przed commitem: `flutter analyze` i `flutter test`.
- GitHub Actions `.github/workflows/build.yml`: testy → iOS na `macos-15-intel`
  (`flutter build ios --no-codesign`, spakowane do `AriView.ipa`) → wydanie `v1.0.<run_number>`.
- Commit z `[skip ci]` w opisie nie uruchamia budowania – używaj go, gdy użytkownik mówi
  „zapisz, ale nie buduj”. Zwykły push na `main` = nowa wersja.
- Link dla użytkownika: `gh api repos/zhuartel-hue/kamery-hd/releases/latest`
  (GraphQL `gh release list` nie działa w sesjach Claude – używaj REST).
- Numer wersji widoczny na dole listy kamer (`APP_VERSION`) – pozwala sprawdzić,
  czy użytkownik ma zainstalowaną najnowszą wersję.

## Wygląd (ustalenia z użytkownikiem)

- Nazwa: **AriView**. Kolor wiodący: nr 12 „Jasny turkus morski” `#5EEAD4` z gradientem
  do `#14B8A6` (`lib/theme.dart`, klasa `Ocean`). Ciemny i jasny motyw.
- Ikona: litera „A” z obiektywem zamiast poprzeczki – `python3 tools/make_icons.py`.
- Obraz kamer bez ramek, na całą szerokość; jedno dotknięcie = pełny ekran;
  przesuwanie palcem = następna/poprzednia kamera; PTZ tylko na żądanie.
- Przyciski „Nagrania” i okrągły „Wróć” na dole po prawej (także w nagraniach).
- Układy (lista, 4, 9, 16, 1+3, 1+5, 1+6, 1+7, 1+12) pod jedną ikoną, zapamiętywane
  osobno dla każdego rejestratora. Przestawianie kamer przeciąganiem.
- Telefon w poziomie: same kamery, jakość HD, na całej szerokości ekranu.

## Kod

- `lib/models/` – kamera (adresy RTSP/HTTP dla obu marek), nagrania, układy.
- `lib/services/camera_api.dart` – ISAPI (Hikvision) i CGI (Dahua): info, zdjęcia, PTZ,
  wykrywanie kanałów, wyszukiwanie nagrań (kilka wariantów zapytań, log w `searchLog`).
- `lib/services/camera_http.dart` – własne uwierzytelnianie Digest (także długie strumienie zdarzeń).
- `lib/services/port_discovery.dart` – automatyczne wykrywanie portów HTTP/RTSP i marki.
- `lib/services/event_parser.dart`, `event_service.dart` – zdarzenia „osoba” z kamer
  (Hikvision alertStream, Dahua eventManager), lista wykryć w `screens/detections_screen.dart`.
- `lib/screens/` – lista kamer, pełny ekran (`live_screen.dart`), nagrania, edycja kamery.
- Wideo: `media_kit` (libmpv). Testy w `test/`.
