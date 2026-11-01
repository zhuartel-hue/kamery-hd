# Plan rozwoju AriView

## Zrobione

- Przestawianie kamer przeciąganiem (wersja 1.0.13).
- Telefon w poziomie = same kamery na całym ekranie (wersja 1.0.13).
- HD i cała szerokość w poziomie, kolor nr 12 #5EEAD4 i nowa ikona (wersja 1.0.15).

- **Automatyczne wykrywanie portów** – przycisk „Wykryj porty automatycznie” w edycji kamery:
  sprawdza porty web (80, 8080, 81…), rozpoznaje markę, odczytuje port RTSP z urządzenia
  (Hikvision `/ISAPI/Security/adminAccess`, Dahua `configManager RTSP`), a gdy się nie da –
  sprawdza typowe porty RTSP (554, 8554, 10554…).
- **Wykrywanie osoby z kamer** – dzwonek na liście kamer: włącznik, lista wykryć ze zdjęciem
  z chwili zdarzenia, powiadomienie w aplikacji. Zdarzenia: Hikvision `alertStream`
  (wtargnięcie, linia, ruch z celem „człowiek”), Dahua `eventManager attach`
  (CrossRegion/CrossLine z Human, SmartMotionHuman). Działa przy otwartej aplikacji.

## Wcześniejsze założenia

1. **Przestawianie kamer przeciąganiem** – klient przytrzymuje kamerę i przeciąga ją
   w inne miejsce (inną „budkę” układu), zamieniając kolejność. Kolejność zapamiętywana
   na telefonie, osobno dla każdego rejestratora/grupy.
2. **Telefon w poziomie = same kamery na całym ekranie** – po obróceniu telefonu znika
   nagłówek, pasek układów i podpisy grup; wybrany układ (4, 9, 16, 1+5, 1+3) wypełnia
   cały ekran bez przewijania. Lista w poziomie: jedna kamera na cały ekran, przewijanie
   kolejnych.

## Szczegóły wersji 1.0.15

- Telefon w poziomie: przeglądane kamery w jakości HD (strumień główny); pełny ekran
  jednej kamery przełącza się na HD po obróceniu, w pionie wraca do ustawienia kamery.
- Telefon w poziomie: obraz na całej szerokości telefonu, bez czarnych pasów po bokach
  (podgląd na żywo i nagrania).
- Kolor wiodący: nr 12 „Jasny turkus morski” #5EEAD4 (gradient do #14B8A6); ikona „A” z obiektywem w tym kolorze.

## Do zbadania

- **Hik-Connect OpenAPI** – użytkownik rejestruje się na tpp.hikvision.com; po uzyskaniu
  dostępu/SDK integrujemy logowanie przez chmurę Hikvision. Dahua – do zbadania.
- **Logowanie klientów przez chmurę** – konto AriView, synchronizacja listy kamer,
  dostęp do kamer spoza sieci domowej (opcje opisane w rozmowie: konto + synchronizacja,
  VPN/DDNS, własny pośrednik w chmurze, chmury producentów).

## Później

- Powiadomienia push przy zamkniętej aplikacji – wymagają płatnego konta Apple Developer
  (99 USD/rok, darmowe Apple ID nie obsługuje push) i serwera pośredniczącego.
- Wyszukiwanie kamer w całej sieci (SADP, ConfigTool, ONVIF WS-Discovery) – na iPhonie
  wymaga zgody Apple na multicast (płatne konto).

- Android (budowanie wyłączone do czasu, gdy aplikacja na iPhone'a będzie gotowa).
- Nagrania z karty SD kamery – czekamy na „Szczegóły techniczne” z prawdziwej kamery.
