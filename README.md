# Belfer — centrum dowodzenia nauczyciela

Natywna aplikacja macOS w SwiftUI. Plan dnia, rozkład materiału, prezentacje, projekty i notatki w jednym miejscu. Interfejs po polsku, bez logowania do Belfra, z lokalnym zapisem danych.

## Uruchomienie na MacBooku

Wymagania: **macOS 14 Sonoma lub nowszy**, **Xcode 16 lub nowszy** (Swift 5.9+ dla Swift Package). Projekt nie wymaga bibliotek zewnętrznych ani kluczy API.

1. Pobierz repozytorium lub wykonaj:
   ```bash
   git clone https://github.com/TenMefo/Belfer_Swift.git
   cd Belfer_Swift
   open Belfer.xcodeproj
   ```
2. W Xcode wybierz schemat **MyApp**, urządzenie **My Mac** i kliknij **Run / ⌘R**.
3. Jeśli Xcode prosi o podpis: w **Signing & Capabilities** wybierz swój Team albo lokalne podpisywanie **Sign to Run Locally**. Zewnętrzny zespół deweloperski nie jest zapisany w projekcie.
4. Dodaj klasę albo wybierz **Zobacz przykład** na kokpicie.

Alternatywnie w Terminalu:

```bash
swift run Belfer
```

Aby utworzyć samodzielną aplikację:

```bash
bash scripts/build-app.sh
open build/Belfer.app
```

Możesz następnie przenieść `build/Belfer.app` do folderu **Aplikacje**. Skrypt buduje aplikację dla architektury bieżącego Maca i podpisuje ją lokalnie (ad hoc). To nie jest wersja notaryzowana przez Apple. Archiwum z Actions jest budowane dla architektury runnera, nie jako universal binary.

## Pierwszy dzień z Belfrem

1. **Klasy** → dodaj klasę, przedmiot i kwalifikację. Dla różnych przedmiotów tej samej klasy utwórz osobne wpisy.
2. **Rozkłady** → dodaj tematy, scenariusze, zadania i wspólne materiały.
3. **Tydzień** → dodaj stałe godziny → **Wypełnij z szablonu**. Ponowne kliknięcie nie dubluje istniejących terminów dla tej samej klasy i godziny. Przesunięty termin może wymagać ręcznego odwołania pierwotnej godziny przed ponownym generowaniem.
4. Otwórz termin → **Edytuj** → przypisz temat, salę i dodatkowe materiały.
5. **Dzisiaj → Przygotuj jutro** pokazuje jutrzejsze lekcje i braki w przygotowaniu.
6. Po lekcji → **Zakończ lekcję** → zapisz, gdzie skończyliście. Notatkę zobaczysz na kolejnej lekcji tej samej klasy i przedmiotu.

Dane przykładowe są ilustracją działania; aplikacja nie pobiera Twoich rzeczywistych plików, rozmów ani planu.

## Dostępne funkcje

- Kokpit wybranego dnia, „Przygotuj jutro”, statusy i lista kontrolna przygotowania.
- Plan tygodnia, stały szablon, generowanie terminów, zmiana daty i wykrywanie kolizji.
- Klasy i przedmioty: liczba zrealizowanych terminów, czas lekcji, ostatni temat i notatka.
- Wspólne tematy z liczbą godzin, scenariuszem, zadaniem i zasobami.
- Niezależny postęp każdej klasy, również przy wspólnych materiałach.
- Pliki i foldery projektów przypinane przez systemowe okno; zakładki macOS pomagają odnaleźć przeniesione pliki.
- Podgląd obsługiwanych dokumentów przez Quick Look i otwieranie w programach domyślnych.
- Rozmowy ChatGPT/Gemini, strony, wiadomości: własne nazwy, linki i instrukcje.
- „Tylko dla nauczyciela”: materiał pomijany przez zbiorcze otwieranie i tryb lekcji. Nie jest to szyfrowanie ani kontrola dostępu do pliku.
- Tryb lekcji w osobnym oknie z dużym poleceniem i materiałami uczniów. Możesz przeciągnąć to okno na projektor albo udostępniać tylko to okno. Kokpit zachowuje prywatne notatki.
- Zadania/pomysły, przypisanie do klasy, terminy, oznaczanie jako wykonane.
- Wyszukiwanie `⌘K` w klasach, tematach, lekcjach, notatkach, zadaniach i nazwach/instrukcjach zasobów. Wyszukiwarka nie indeksuje wnętrza plików.
- Kopiowanie tematu do Librusa i polecenia dla uczniów.
- Import CSV z podsumowaniem i pomijaniem duplikatów temat + przedmiot.
- Automatyczny atomowy zapis, poprzedni poprawny stan oraz eksport/przywracanie kopii JSON z walidacją.

## Import rozkładu z Excela

W Excelu przygotuj arkusz z kolumnami `temat`, `przedmiot`, `godziny`, następnie zapisz jako **CSV UTF-8**. Obsługiwane są separatory `;` i `,`, BOM, cudzysłowy, średniki oraz nowe linie wewnątrz cytowanych pól.

```csv
temat;przedmiot;godziny
Checkbox, radio i select;Tworzenie stron i aplikacji internetowych;2
JSX i komponenty;Tworzenie aplikacji webowych;2
```

`temat` jest wymagany. Pominięta kolumna `godziny` oznacza 1. Jeśli kolumna istnieje, wartości muszą być liczbami całkowitymi 1–1000. Kolumna `przedmiot` jest opcjonalna; jej tekst powinien odpowiadać przedmiotowi wpisanemu przy klasie. Przykład: `examples/rozklad.csv`.

Import **dodaje nowe tematy**, nie nadpisuje istniejących. Zmiany rozkładu edytuj w aplikacji. Bezpośredni import `.xlsx`, mapowanie dowolnych kolumn i porównywanie wersji nie są jeszcze zaimplementowane.

## Integracje — rzeczywisty zakres wersji 0.1

| Narzędzie | Co działa |
| --- | --- |
| Librus | Skrót do strony i kopiowanie tematu. Bez logowania/synchronizacji danych dziennika. |
| ChatGPT / Gemini | Prywatne linki do rozmów otwierane w przeglądarce. Bez pobierania historii ani generowania AI. |
| Poczta | `mailto:`, `message:` oraz pliki `.eml`. Bez pobierania skrzynki. |
| Excel | Import CSV UTF-8. Bez odczytu `.xlsx`. |
| Projekty | Otwieranie folderów w Finderze, plików w domyślnych programach i zapis instrukcji. Bez wykonywania komend. |

Nie potrzebujesz publicznego linku do rozmowy — przypnij jej zwykły adres i korzystaj z zalogowanej przeglądarki. Dla wiadomości Apple Mail można przypiąć adres `message:` z identyfikatorem wiadomości; inne aplikacje mogą go nie obsługiwać.

## Dane i kopie

Dane trafiają do `~/Library/Application Support/Belfer/workspace.json`. Po każdym kolejnym poprawnym zapisie poprzedni stan jest zachowywany jako `workspace.previous.json`. Ustawienia → **Pokaż folder danych** otwiera właściwą lokalizację.

- Błąd odczytu blokuje zapis i nie nadpisuje uszkodzonego pliku.
- Przywracanie kopii wymaga potwierdzenia. Przed zastąpieniem bieżący plik zostaje zachowany pod unikalną nazwą.
- Kopie JSON zawierają notatki, ścieżki i zakładki plików, więc przechowuj je jak własne materiały nauczyciela.
- Prezentacje i projekty pozostają poza kopią — wykonuj również ich backup.
- Aplikacja desktopowa działa bez App Sandbox, aby oba sposoby uruchamiania miały jednakowy dostęp do wskazanych zasobów. Materiałów nie wysyła na serwer; otwieranie zewnętrznych linków odbywa się przez domyślne aplikacje.
- Wersja 0.1 jest przeznaczona do jednego procesu aplikacji naraz; jednoczesne uruchomienie kilku kopii nie ma mechanizmu scalania zmian.

## Rozwój i sprawdzanie

```bash
swift test
bash scripts/build-app.sh
xcodebuild -project Belfer.xcodeproj -scheme MyApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Workflow `.github/workflows/macos.yml` sprawdza testy, kompilację Swift Package i projektu Xcode oraz udostępnia archiwum aplikacji w artefaktach **Actions → macOS build and tests → Belfer-macOS**.

Źródła:
- `Belfer/Core/` — modele, reguły planowania, walidacja i parser CSV.
- `Belfer/WorkspaceStore.swift` — zapis, kopie, import i obsługa zasobów macOS.
- `Belfer/*Views.swift`, `ContentView.swift`, `Editors.swift` — interfejs SwiftUI.
- `Tests/BelferTests/` — parser, plan tygodnia, kolizje, powiązania i odporność zapisu.

Dalszy plan: bezpośredni Excel z mapowaniem kolumn i różnicami; kalendarz/święta/wyjątki; uruchamianie wybranego edytora; dopiero po weryfikacji możliwości dostawców odczyt poczty i Librusa. Te funkcje nie są oznaczane jako działające w obecnej wersji.
