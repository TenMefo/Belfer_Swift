# Belfer 0.3 — centrum dowodzenia nauczyciela

Natywna aplikacja macOS w SwiftUI. Dane lokalne, interfejs po polsku, bez konta Belfer i zewnętrznych bibliotek. **macOS 14+**, projekt Xcode 16+ lub Swift Package ze Swift 5.9+.

## Uruchomienie

```bash
git clone https://github.com/TenMefo/Belfer_Swift.git
cd Belfer_Swift
open Belfer.xcodeproj
```

W Xcode: schemat **MyApp**, urządzenie **My Mac**, **⌘R**. W razie potrzeby ustaw lokalne podpisywanie **Sign to Run Locally** lub swój Team.

Alternatywnie:

```bash
swift run Belfer
bash scripts/build-app.sh
open build/Belfer.app
```

`build/Belfer.app` możesz przenieść do Aplikacji. Paczka jest podpisana lokalnie (ad hoc), bez notaryzacji Apple. Budowa lokalna odpowiada architekturze Twojego Maca; artefakt Actions odpowiada architekturze runnera (Apple Silicon). Paczkę znajdziesz w **Actions → macOS build and tests → Belfer-macOS**.

## Organizacja 0.3: przedmiot → rozkład → temat → lekcja

1. **Przedmioty** → dodaj przedmiot, np. Tworzenie stron i aplikacji internetowych.
2. **Klasy** → dodaj klasę i wybierz przedmiot. Ta sama klasa dla innego przedmiotu ma osobny wpis i historię.
3. **Rozkłady** → najpierw wybierz przedmiot, następnie jego rozkład. Dodaj rozkład ręcznie lub zaimportuj Excel.
4. Dodaj tematy, ich kolejność, godziny, scenariusze i zadania. Temat należy do jednego przedmiotu i rozkładu.
5. W edycji lekcji wybierz **przedmiot**, klasę tego przedmiotu, rozkład i temat. Lista nie miesza tematów innych przedmiotów.
6. **Uruchamianie** → wybierz przedmiot i przypisz jego skróty oraz profile środowiska.

Przedmiot ma trwały identyfikator, więc zmiana jego nazwy nie zrywa powiązań. Aplikacja odrzuca zapis tematu, profilu lub skrótu, który nie pasuje do przedmiotu lekcji. Ogólne skróty bez przypisania są dostępne niezależnie od przedmiotu; nie należy zostawiać XAMPP jako ogólnego, jeśli ma służyć tylko jednemu przedmiotowi.

## Kokpit i planowanie

- Dzisiaj / jutro / dowolny dzień, lista lekcji i brakujących przygotowań.
- Rozwijany podgląd przygotowania najbliższych 7 dni oraz zadania do wykonania.
- Stały plan godzin, generowanie tygodnia bez dublowania tej samej klasy i godziny, oznaczanie kolizji.
- **Blok 1–10 lekcji** w jednym terminie, wspólne materiały i scenariusz; domyślnie 45 min na godzinę. Czas całego bloku można dostosować.
- **Plan i kontynuacja**: kopia lekcji na wybraną datę, kontynuacja z notatką „co dalej”, przesunięcie kolejnych niezrealizowanych terminów klasy/przedmiotu o liczbę dni.
- Punkty kontrolne w bloku zapisują się z godziną w notatkach.
- Ostatni zrealizowany temat i notatka klasy, szybkie otwarcie jego edycji.
- Zakończenie lekcji zapisuje postęp; kartkówki, wycieczki i zastępstwa można opisywać oraz zmieniać ręcznie. Przesuwanie nie oblicza kalendarza świąt ani zastępstw automatycznie.

Zmiana szablonu godzin nie zmienia już utworzonych terminów. Po przesunięciu terminu ponowne generowanie tygodnia może odtworzyć pierwotną godzinę; odwołaj ją albo usuń według potrzeb. Powiązanie kontynuacji zachowuje temat i materiały; nie wycina automatycznie części scenariusza.

## Excel i CSV: mapowanie oraz podgląd zmian

W **Rozkłady** wybierz przedmiot → **Import Excel / CSV**:

1. Wskaż `.xlsx` lub CSV UTF-8.
2. Wybierz arkusz, wiersz nagłówków, kolumnę tematu i opcjonalnie godzin.
3. Wybierz istniejący rozkład albo nazwę nowego.
4. Kliknij **Porównaj z rozkładem**. Zobaczysz nowe i zmienione tematy.
5. Kliknij **Zastosuj zmiany**.

Godziny muszą być liczbami całkowitymi 1–1000. Bez kolumny godzin przyjmowana jest 1. CSV obsługuje separator `;` lub `,`, BOM, pola cytowane i nowe linie w cytowanych polach. XLSX obsługuje wiele arkuszy, shared strings, inline strings, tekst i liczby; dla formuł odczytuje wartość zapisaną w pliku, bez przeliczania. Zapisz i przelicz arkusz w Excelu przed importem. Format `.xls` i pliki chronione hasłem nie są obsługiwane.

Dopasowanie aktualizacji następuje po nazwie tematu **wewnątrz wybranego rozkładu**. Materiały, scenariusz i identyfikator istniejącego tematu pozostają. Zmiana nazwy jest nowym tematem. Tematy nieobecne w pliku są zachowywane — import nie usuwa ich. Dane trafiają wyłącznie do wybranego przedmiotu; kolumny z nazwami innych przedmiotów w pliku nie zmieniają tego wyboru.

## Środowiska, aplikacje, XAMPP i serwery React

**Uruchamianie**: wybierz przedmiot → **Dodaj przyciski XAMPP**. Powstaną start/stop/restart/status przypisane do tego przedmiotu. Domyślny program: `/Applications/XAMPP/xamppfiles/xampp` (klasyczna instalacja macOS, nie XAMPP-VM). Zmień ścieżkę w edycji, jeśli instalacja jest inna. Belfer nie instaluje ani nie konfiguruje XAMPP.

Start/stop/restart korzystają z systemowego uwierzytelnienia administratora przez AppleScript. Nie dodawaj `sudo`. Hasło nie jest przechowywane przez Belfra. Status domyślnie działa bez administratora; możesz zmienić tę opcję dla swojej instalacji.

**VS Code**: wybierz `.app` i folder projektu. Nie trzeba instalować polecenia `code` w PATH. Możesz użyć innego edytora lub aplikacji.

**Profile środowiska**: wybierz przedmiot, nazwij zestaw i zaznacz akcje, np. VS Code i start XAMPP. Wybierz profil w edycji lekcji. Przycisk profilu uruchamia zestaw; otwarcie materiałów również uruchamia akcje profilu. Kolejność odpowiada kolejności akcji, a błąd przerywa zestaw. Akcje w profilu muszą być ogólne lub przypisane do jego przedmiotu.

**Serwer React / Vite**: preset korzysta z `/opt/homebrew/bin/npm` i argumentów `run`, `dev`, adresu `http://localhost:5173`. Wybierz folder projektu, ustaw faktyczną lokalizację npm i adres strony. Node/npm oraz zależności projektu muszą być zainstalowane. Opcja **Proces działający w tle** dodaje osobne przyciski startu, zatrzymania, logu i strony. Serwer działa do zatrzymania; wyłączenie Belfra wysyła sygnał zakończenia do uruchomionych przez niego procesów. Belfer nie przejmuje procesów uruchomionych wcześniej poza aplikacją.

Polecenia jednorazowe mają limit 3 minut. Procesy w tle nie mają tego limitu i nie mogą żądać administratora. Program i argumenty mają osobne pola, więc spacje/apostrofy w ścieżkach są przekazywane dosłownie. Dla operatorów powłoki wybierz `/bin/zsh`, argument `-lc` i treść polecenia w kolejnym wierszu. Nie zapisuj haseł/tokenów w akcjach.

Skróty przedmiotu pokazują się przy jego lekcjach i na kokpicie po wybraniu jednej z nich; nie pojawiają się przy innych przedmiotach. Akcja może być dodatkowo ograniczona do tematu lub terminu. Opcja „razem z materiałami” uruchamia ją po kliknięciu przycisku otwarcia materiałów. Akcje nie startują przy samym wczytaniu danych. XAMPP zatrzymujesz osobnym przyciskiem.

Wynik kod 0 potwierdza zakończenie polecenia, nie stan usług. Użyj Status XAMPP lub logu serwera. Usługi mogą startować z opóźnieniem. Po przekroczeniu czasu polecenia sprawdź stan usług — zakończenie programu uruchamiającego nie musi wyłączyć usług.

## Materiały, uczniowie i AI

- Pliki, foldery i linki przypinasz ręcznie lub przeciągasz na kartę lekcji. Przycisk **Wklej link** przypina adres ze schowka.
- Materiał ma rolę: materiał ucznia, projekt startowy albo rozwiązanie nauczyciela. Rozwiązanie jest zawsze wykluczone z pakietów i widoku ucznia, także po odznaczeniu zwykłej opcji prywatności.
- **Nowa kopia projektu startowego** tworzy nowy folder o unikalnej nazwie, bez nadpisywania źródła. Folder docelowy musi być poza projektem.
- **Pakiet ucznia ZIP**: wybierz zasoby. ZIP zawiera polecenie, wybrane pliki/foldery i odnośniki. Kopiowanie pomija `.git`, `node_modules`, `.build`, `.env*`, `.DS_Store` i dowiązania symboliczne. Oznacz rozwiązania jako prywatne i sprawdź zawartość folderu projektu, który wybierasz do udostępnienia.
- Tryb lekcji w osobnym oknie na projektor zawiera zadanie i materiały uczniów, bez notatek nauczyciela.
- Zadanie do sprawdzenia można powiązać z klasą, terminem i folderem prac.
- **Kontekst do ChatGPT / Gemini** kopiuje do schowka temat, czas, klasę, notatki, scenariusz i nazwy materiałów. Nie odczytuje plików ani nie wysyła danych do AI. Przed wklejeniem możesz usunąć prywatne uwagi.
- Wyszukiwanie `⌘K` obejmuje nazwy, tematy, notatki i przypięcia; nie indeksuje wnętrza plików.

## Kopie i aktualizacja z 0.1 / 0.2

Dane: `~/Library/Application Support/Belfer/workspace.json`. Poprzedni poprawny stan: `workspace.previous.json`. Zapis jest atomowy; uszkodzony plik blokuje dalszy zapis. Kopia JSON obejmuje dane i przypięcia, bez plików materiałów.

Wersja 0.3 odczytuje stare kopie i przypisuje dawne nazwy przedmiotów do identyfikatorów, tworzy rozkłady i zachowuje terminy, notatki oraz materiały. Dawne nieprawidłowo przypisane tematy lekcji są kopiowane do właściwego przedmiotu, aby nie zgubić materiałów. Stare ogólne skróty pozostają ogólne; przypisz im przedmiot w Uruchamianiu. Nie otwieraj zapisanych danych 0.3 w starszym Belfrze.

**Ustawienia → Automatyczne kopie**: wybierz folder. Po zapisie powstaje kopia; zachowywanych jest ostatnich 30 plików o prefiksie `Belfer-auto-`. Niedostępny folder kopii zgłasza osobny komunikat; lokalny zapis nadal pozostaje poprawny. Wykonuj również kopie samych prezentacji i projektów.

Aplikacja działa lokalnie bez App Sandbox. Pliki otwierają się w programach domyślnych. Przeznaczona jest do jednej uruchomionej kopii Belfra naraz; brak scalania równoległych zapisów.

## Integracje i granice

Librus: odnośnik i kopiowanie tematu, bez synchronizacji dziennika. Poczta: przypięte pliki i linki `mailto:` / `message:`, bez odczytu skrzynki. ChatGPT/Gemini: prywatne adresy rozmów i kontekst do skopiowania, bez pobierania historii i generowania przez API.

Rzeczywiste uruchamianie XAMPP, edytorów, portów Vite, systemowego okna administratora i projektora wymaga sprawdzenia na Macu z odpowiednim oprogramowaniem. CI sprawdza kompilację i automatyczne testy, bez takiej instalacji użytkownika.

## Testy

```bash
swift test
bash scripts/build-app.sh
xcodebuild -project Belfer.xcodeproj -scheme MyApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Workflow macOS wykonuje wszystkie te kroki i udostępnia ZIP aplikacji. Testy obejmują m.in. migrację, izolację przedmiotów, import XLSX/CSV, aktualizacje rozkładu, kontynuację i przesuwanie, kopiowanie plików oraz start/log/zatrzymanie procesu w tle.
