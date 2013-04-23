# 4.4rc2+PL@aviary.pl 
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#
# Translated by Zespół Aviary.pl <team@aviary.pl>

# This file contains a single hash named %strings, which is used by the
# installation code to display strings before Template-Toolkit can safely
# be loaded.
#
# Each string supports a very simple substitution system, where you can
# have variables named like ##this## and they'll be replaced by the string
# variable with that name.
#
# Please keep the strings in alphabetical order by their name.

%strings = (
    any  => 'dowolna',
    apachectl_failed => <<END,
OSTRZEZENIE: Nie mozna bylo sprawdzic konfiguracji Apache. To sie czasami 
zdarza, gdy skrypt checksetup.pl zostal uruchomiony z innego konta niz ##root##.
Aby zobaczyc znalezione bledy, wykonaj polecenie:
##command##
END
    bad_executable => 'nieprawidlowy plik wykonywalny: ##bin##',
    blacklisted => 'zablokowana',
    bz_schema_exists_before_220 => <<'END',
Podczas wykonywania aktualizacji z wersji wczesniejszej niz 2.20 wykryto, ze
tablica bz_schema juz istnieje. Oznacza to, ze odtworzono kopie bazy danych 
Bugzilli utworzona narzedziem mysqldump bez uprzedniego wykonania polecenia drop
na bazie danych. Przed przywroceniem kopii bazy danych Bugzilli nalezy kazdorazowo
wykonywac polecenie drop na bazie danych.

Prosze wykonac polecenie drop na bazie danych Bugzilli, a nastepnie odtworzyc
baze danych Bugzilli, ktora nie zawiera tablicy bz_schema. W ostatecznosci, 
jesli z jakiegos powodu nie mozna wykonac tej operacji, nalezy polaczyc sie 
z serwerem MySQL i wykonac polecenie drop na tabeli bz_schema.



END
    checking_for => 'Sprawdzanie',
    checking_dbd      => 'Sprawdzanie dostepnych modulow Perl DBD...',
    checking_optional => 'Nastepujace moduly Perla sa opcjonalne:',
    checking_modules  => 'Sprawdzanie modulow Perl...',
    chmod_failed      => '##path##: Nie udalo sie zmienic uprawnien: ##error##',
    chown_failed      => '##path##: Nie udalo sie zmienic wlasnosci: ##error##',
    commands_dbd      => <<EOT,
NALEZY URUCHOMIC JEDNO Z NASTEPUJACYCH POLECEN (w zaleznosci od uzywanej bazy danych):
EOT
    commands_optional => 'POLECENIA DO ZAINSTALOWANIA OPCJONALNYCH MODULOW:',
    commands_required => <<EOT,
POLECENIA DO ZAINSTALOWANIA WYMAGANYCH MODULOW (*Musisz* uruchomic wszystkie 
te polecenia i nastepnie ponownie uruchomic skrypt checksetup.pl):
EOT
    continue_without_answers => <<'END',
Uruchom checksetup.pl w trybie interakcyjnym (bez pliku 'answers')
by kontynuowac.
END
    cpan_bugzilla_home => 
        "OSTRZEZENIE: Katalog Bugzilla uzywany jako katalog domowy CPAN.",
    db_enum_setup  => "Tworzenie wartosci dla domyslnego zestawu pol wyboru:",
    db_schema_init => "Inicjalizowanie bz_schema...",
    db_table_new   => "Dodawanie tabeli ##table##...",
    db_table_setup => "Tworzenie tabel...",
    done => 'zakonczono.',
    enter_or_ctrl_c => "Nacisnij Enter, aby kontynuowac lub Ctrl-C, aby zakonczyc...",
    error_localconfig_read => <<'END',

Podczas odczytu pliku ##localconfig## wystapil blad. Komunikat bledu:

##error##

Prosze naprawic bledy w pliku localconfig. Alternatywnie mozna zmienic nazwe
pliku i uruchomic skrypt checksetup.pl, ktory utworzy nowy plik localconfig:


  $ mv -f localconfig localconfig.old
  $ ./checksetup.pl
END
    extension_must_return_name => <<END,
##file## zwrocil ##returned##, ktory nie jest poprawna nazwa rozszerzenia.
Rozszerzenia musza zwracac swoja nazwe, a nie <code>1</code> lub numer. Wiecej
szczegolow znajdziesz w dokumentacji Bugzilla::Extension.
END
    feature_auth_ldap         => 'Uwierzytelnianie LDAP',
    feature_auth_radius       => 'Uwierzytelnianie RADIUS',
    feature_graphical_reports => 'Raporty graficzne',
    feature_html_desc         => 'Wiecej HTML w opisach Produktu/Grupy',
    feature_inbound_email     => 'E-mail przychodzacy',
    feature_jobqueue          => 'Kolejkowanie poczty',
    feature_jsonrpc           => 'Interfejs JSON-RPC',
    feature_jsonrpc_faster    => 'Przyspiesza interfejs JSON-RPC',
    feature_new_charts        => 'Nowe wykresy',
    feature_old_charts        => 'Stare wykresy',
    feature_mod_perl          => 'mod_perl',
    feature_moving            => 'Przenoszenie bledow pomiedzy instalacjami',
    feature_patch_viewer      => 'Przegladarka latek',
    feature_smtp_auth         => 'Uwierzytelnianie SMTP',
    feature_smtp_ssl          => 'Szyfrowanie SSL dla polaczen SMTP',
    feature_updates           => 'Automatyczne powiadomienia o aktualizacji',
    feature_xmlrpc            => 'Interfejs XML-RPC',
    feature_detect_charset    => 'Automatyczne wykrywanie strony kodowej zalacznikow tekstowych',
    feature_typesniffer       => 'Automatyczne wykrywanie typu MIME zalacznikow',

    file_remove => 'Usuwanie ##name##...',
    file_rename => 'Zmienianie nazwy ##from## na ##to##…',
    header => "* To jest Bugzilla ##bz_ver## wraz z Perl ##perl_ver##\n"
            . "* Uruchomiono na ##os_name## ##os_ver##",
    install_all => <<EOT,

Aby sprobowac automatycznie zainstalowac wszystkie wymagane i opcjonalne moduly
za pomoca jednego polecenia, wykonaj:

  ##perl## install-module.pl --all

EOT
    install_data_too_long => <<EOT,
OSTRZEZENIE: Niektore dane zawarte w kolumnie ##table##.##column## sa dluzsze niz
dozwolony nowy limit wynoszacy ##max_length## znakow. Dane wymagajace poprawienia
zostaly wyswietlone ponizej w nastepujacej kolejnosci: najpierw dla kolumny ##id_column## 
i nastepnie dla kolumny wymagajacej naprawienia ##column##:

EOT
    install_module => 'Instalowanie modulu ##module## wersja ##version##...',
    installation_failed => '*** Instalacja zostala przerwana. Prosze przeczytac powyzsze komunikaty bledow. ***',
    install_no_compiler => <<END,
BLAD: Korzystanie ze skryptu install-module.pl wymaga wczesniejszej instalacji kompilatora, takiego jak
gcc.
END
    install_no_make => <<END,
BLAD: Korzystanie ze skryptu install-module.pl wymaga wczesniejszej instalacji programu "make".
END
    lc_new_vars => <<'END',
Ta wersja Bugzilli zawiera zmienne, ktore mozna zmienic lub dostosowac do wymagan
lokalnej instalacji. Do pliku ##localconfig## dodano nastepujace nowe zmienne 
od ostatniego uruchomienia skryptu checksetup.pl:  


##new_vars##


Prosze zmodyfikowac plik ##localconfig## i uruchomic skrypt checksetup.pl.
END
    lc_old_vars => <<'END',
Nastepujace zmienne nie sa juz wykorzystywane w pliku ##localconfig##, wiec
zostaly przeniesione do pliku ##old_file##: ##vars##

END
    localconfig_create_htaccess => <<'END',
W przypadku korzystania z serwera www Apache, Bugzilla moze utworzyc odpowiednie pliki
.htaccess, ktore uniemozliwia odczyt z sieci pliku localconfig oraz innych poufnych
informacji.

Wartosc 1 oznacza, ze checksetup.pl utworzy pliki .htaccess, jesli nie  
istnieja.

Wartosc 0 oznacza, ze checksetup.pl nie bedzie tworzyl plikow .htaccess.
END
    localconfig_cvsbin => <<'END',
Podaj sciezke do pliku wykonywalnego cvs, jesli chcesz wykorzystywac funkcje 
integracji systemu kontroli wersji CVS z Patch Viewerem.

END
    localconfig_db_check => <<'END',
Czy skrypt checksetup.pl powinien sprawdzac poprawnosc konfiguracji bazy danych?
W przypadku niektorych kombinacji wykorzystywanych serwerow bazy danych, modulow Perl 
czy faz ksiezyca sprawdzenie moze nie zadzialac. Wartosc 0 wylacza sprawdzanie
umozliwiajac poprawne dzialanie skryptu checksetup.pl.
  
END
    localconfig_db_driver => <<'END',
Wykorzystywany serwer baz danych SQL. Domyslnie jest to mysql. Liste obslugiwanych
serwerow mozna sprawdzic poprzez wyswietlenie zawartosci katalogu
Bugzilla/DB. Obsluge serwerow baz danych zapewniaja okreslone moduly, ktorych 
nazwa (przed rozszerzeniem ".pm") okresla prawidlowa wartosc dla tej zmiennej.
END
    localconfig_db_host => <<'END',
Nazwa DNS lub adres IP komputera, na ktorym jest uruchomiony serwer baz danych.
END
    localconfig_db_name => <<'END',
Nazwa bazy danych. W przypadku Oracle jest to SID bazy. W przypadku SQLite
jest to nazwa (lub sciezka do) pliku DB.
END
    localconfig_db_pass => <<'END',
Haslo dostepu do bazy danych. Zaleca sie, aby bylo to haslo zdefiniowane dla 
uzytkownika bazy danych bugzilli.
W przypadku, gdy haslo zawiera znak apostrofu (') lub odwrotny ukosnik (\), 
nalezy poprzedzic je znakiem '\', np. (\') lub (\\).
(Prosciej jest jednak nie uzywac tych znakow.)

END
    localconfig_db_port => <<'END',
Zdarza sie, ze serwer baz danych jest uruchomiony na niestandardowym porcie. W takim
przypadku nalezy okreslic odpowiedni port. Wartosc 0 oznacza "uzyj domyslnego
portu serwera baz danych".

END
    localconfig_db_sock => <<'END',
Tylko MySQL: wprowadz sciezke do gniazda serwera MySQL. Pozostawione puste sprawi,
ze wykorzystywane bedzie gniazdo zdefiniowane przy kompilacji MySQL. Prawdopodobna 
wartosc parametru.

END
    localconfig_db_user => "Nazwa uzytkownika do polaczenia z baza danych.",
    localconfig_diffpath => <<'END',
Funkcja "Roznice pomiedzy latkami" wymaga okreslenia katalogu, w ktorym znajduje sie 
program "diff".
(Wartosc nalezy okreslac tylko w przypadku wykorzystywania tej funcjonalnosci Patch
Viewera). 
END
    localconfig_index_html => <<'END',
Wiekszosc serwerow stron www zezwala na wykorzystywanie pliku index.cgi jako 
glownego pliku katalogu strony i jest prekonfigurowana w ten sposob. Jesli
jednak w twoim przypadku jest inaczej, to nalezy utworzyc plik index.html, ktory
przekieruje wywolanie do pliku index.cgi. Wartosc 1 dla $index_html pozwoli na
automatyczne utworzenie pliku index.html przez skrypt checksetup.pl, jesli plik 
nie istnieje.
UWAGA: skrypt checksetup.pl nie nadpisze istniejacego pliku, wiec aby operacja
       utworzenia pliku index.html sie powiodla, nalezy upewnic sie, ze plik
	   o tej nazwie nie istnieje.
END
    localconfig_interdiffbin => <<'END',
Funkcja "Roznice pomiedzy latkami" Patch Viewera wymaga okreslenia pelnej sciezki do pliku
wykonywalnego "interdiff".
END
    localconfig_site_wide_secret => <<'END',
Wartosc klucza prywatnego wykorzystywana jest przez instalacje do generowania
oraz walidacji zaszyfrowanych tokenow. Sa one wykorzystywane do zabezpieczenia
instalacji Bugzilli przed atakami roznego typu. Domyslnie generowany jest
losowy ciag znakow. Bardzo wazne jest, aby chronic wartosc tego klucza oraz aby
byl to dlugi ciag znakow.
END
    localconfig_use_suexec => <<'END',
Ustaw wartosc 1 jesli Bugzilla jest uruchomiona w srodowisku SuexecUserGroup serwera Apache.

W przypadku, gdy do zarzadzania serwerem www wykorzystywany jest panel administracyjny (cPanel, 
Plesk lub podobny), badz Bugzilla uruchomiona jest w srodowisku hostingu wspoldzielonego, wtedy 
z bardzo duza pewnoscia mozna stwierdzic, ze bedzie uruchamiana w srodowisku SuexecUserGroup
Apache.

Ustawienie jest ignorowane, gdy wykorzystywany jest system Windows.

Wartosc 0 oznacza, ze skrypt checksetup.pl nada prawidlowe uprawnienia dla plikow
w standardowym srodowisku serwera www. 

Wartosc 1 oznacza, ze skrypt checksetup.pl nada niezbedne uprawnienia tak, aby Bugzilla
mogla pracowac w srodowisku SuexecUserGroup serwera Apache.

END
    localconfig_webservergroup => <<'END',
Nazwa grupy zabezpieczen serwera www. W dystrybucjach Red Hat
jest to zwykle grupa "apache". W przypadku Debiana/Ubuntu, jest to 
zwykle "www-data".

W przypadku wlaczenia ponizszego parametru use_suexec, wpis ten bedzie okreslal
grupe zabezpieczen, z poziomu ktorej beda wykonywane pliki cgi.

Ustawienie jest ignorowane, gdy wykorzystywany jest system Windows.

W przypadku braku dostepu do grupy zabezpieczen, z poziomu ktorej beda
wykonywane skrypty, nalezy wpisac wartosc "". W takim wypadku instalacja Bugzilli
bedzie BARDZO niebezpieczna, gdyz czesc plikow bedzie dostepna do odczytu/zapisu globalnie. 
W takim wypadku kazdy, kto bedzie miec lokalny dostep do systemu, moze wykonac na
tych plikach dowolna czynnosc. Wartosc "" powinna zostac okreslona tylko w instalacjach
testowych. ZOSTALES OSTRZEZONY!

W przypadku okreslenia tej wartosci jako innej niz "",
skrypt checksetup.pl bedzie musial byc wykonywany jako ##root## lub uzytkownika
bedacego czlonkiem okreslonej powyzej grupy.
END
    max_allowed_packet => <<EOT,
OSTRZEZENIE: Nalezy ustawic parametr max_allowed_packet w swojej konfiguracji bazy danych MySQL
przynajmniej na wartosc ##needed##. Obecna wartosc to ##current##.
Ten parametr mozna ustawic w pliku konfiguracyjnym bazy danych MySQL
w sekcji [mysqld].
EOT
    min_version_required => "Minimalna wymagana wersja: ",

# Note: When translating these "modules" messages, don't change the formatting
# if possible, because there is hardcoded formatting in 
# Bugzilla::Install::Requirements to match the box formatting.
    modules_message_apache => <<END,
***********************************************************************
* MODULY APACHE                                                       *
***********************************************************************
* Zwykle po przeprowadzeniu aktualizacji wszyscy uzytkownicy          *
* Bugzilli musza wyczyscic pamiec podreczna przegladarki, gdyz w      *
* przeciwnym wypadku Bugzilla moze ulec awarii. Jesli w pliku         *
* konfiguracyjnym (httpd.conf lub apache2.conf) serwera Apache        *
* zostana wlaczone odpowiednie moduly, to uzytkownicy nie beda        *
* zmuszeni do czyszczenia pamieci podrecznej przegladarki po          *
* aktualizacji Bugzilli. Nalezy wlaczyc nastepujace moduly:           *
*                                                                     *
END
    modules_message_db => <<EOT,
***********************************************************************
* DOSTEP DO BAZY DANYCH                                               *
***********************************************************************
* Aby uzyskac dostep do twojej bazy danych, Bugzilla wymaga, aby      *
* dla uruchomionej bazy byl prawidlowo zainstalowany modul "DBD".     *
* Zobacz ponizej poprawne polecenia do uruchomienia instalacji modulu *
* odpowiedniego dla twojej bazy danych.                               *
EOT
    modules_message_optional => <<EOT,
***********************************************************************
* OPCJONALNE MODULY                                                   *
***********************************************************************
* Niektore moduly Perla nie sa wymagane do prawidlowego dzialania     *
* Bugzilli, ale, instalujac najnowsza wersje, uzyskasz dostep do      *
* dodatkowych funkcji.                                                *
*                                                                     *
* Ponizej znajduje sie lista niezainstalowanych opcjonalnych modulow  *
* z opisem funkcji, ktore beda dostepne po ich instalacji. W tabeli   *
* znajduja sie polecenia ulatwiajace instalacje kazdego modulu.       *
EOT
    modules_message_required => <<EOT,
***********************************************************************
* WYMAGANE MODULY                                                     *
***********************************************************************
* Bugzilla wymaga zainstalowania kilku modulow Perla, ktorych brakuje *
* w tym systemie lub ich wersje sa nieaktualne.                       *
* Ponizej znajduja sie polecenia do zainstalowania tych modulow.      *
EOT

    module_found => "znaleziono v##ver##",
    module_not_found => "nie znaleziono",
    module_ok => 'ok',
    module_unknown_version => "znaleziono nieznana wersje",
    no_such_module => "W repozytorium CPAN nie znaleziono modulu Perl o nazwie ##module##.",
    mysql_innodb_disabled => <<'END',
W twojej instalacji MySQL mechanizm InnoDB jest wylaczony.
Bugzilla wymaga, aby byl on wlaczony.
Po wlaczeniu nalezy uruchomic skrypt checksetup.pl.
END
    mysql_index_renaming => <<'END',
Wymagana jest zmiana nazw indeksow. Szacunkowy czas wykonywania operacji wyniesie
##minutes## minut. Nie mozna przerwac operacji po jej rozpoczeciu. Aby przerwac,
nalezy teraz wcisnac Ctrl-C...
(Rozpoczecie operacji za 45 sekund...)
END
    mysql_utf8_conversion => <<'END',
OSTRZEZENIE: Nastapi konwersja tabel na format UTF-8. Pozwala to na prawidlowe
		 przechowywanie i sortowanie znakow narodowych. Jednakze, jesli w bazie danych
		 znajduja sie dane niesformatowane jako UTF-8, to zostana one
		 ***USUNIETE***. Nalezy przerwac dzialanie skryptu checksetup.pl kombinacja
		 klawiszy Ctrl-C, jesli w bazie znajduja sie dane zapisane w formacie
		 innym niz UTF-8 lub gdy nie jestesmy tego pewni. Nastepnie nalezy uruchomic
		 skrypt contrib/recode.pl, aby przekonwertowac dane na format UTF-8. Zaleca
		 sie wykonanie kopii zapasowej bazy danych, gdyz konwersja moze dotyczyc tabel
		 innych niz Bugzilli.
		 
		 W przypadku korzystania z Bugzilli w wersji wczesniejszej niz 2.22
		 ZALECAMY przerwanie dzialania skryptu TERAZ i uruchomienie contrib/recode.pl.
END
    no_checksetup_from_cgi => <<END,
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN"
          "http://www.w3.org/TR/html4/strict.dtd">
<html>
  <head>
    <title>checksetup.pl nie może zostać uruchomiony za pomocą przeglądarki</title>
  </head>

  <body>
    <h1>checksetup.pl nie może zostać uruchomiony za pomocą przeglądarki</h1>
    <p>
      <b>Nie wolno</b> uruchamiać tego skryptu za pomocą przeglądarki.
      Instalacja lub aktualizacja Bugzilli musi być wykonana
      z linii poleceń (np. <tt>bash</tt> lub poprzez sesję <tt>ssh</tt> dla Linuksa
      lub <tt>cmd.exe</tt> dla Windows), zgodnie z podanymi instrukcjami.
    </p>

    <p>
      Więcej informacji o procesie instalacji Bugzilli znajduje się w
      <a href="http://www.bugzilla.org/docs/">dokumentacji</a>
      dostępnej na oficjalnej stronie internetowej Bugzilli.
    </p>
  </body>
</html>
END
    patchutils_missing => <<'END',
UWAGA: Aby korzystac z funkcji "Roznice pomiedzy latkami" (ktora wymaga instalacji modulu
Perl PatchReader) nalezy zainstalowac pakiet patchutils ze strony:

    http://cyberelk.net/tim/patchutils/
END
    ppm_repo_add => <<EOT,
***********************************************************************
* Informacja dla uzytkownikow systemu Windows                         *
***********************************************************************
* Aby zainstalowac wymienione ponizej moduly, nalezy najpierw jako    * 
* Administrator uruchomic nastepujace polecenie:                      *
*                                                                     *
*   ppm repo add theory58S ##theory_url##
EOT
    ppm_repo_up => <<EOT,
*                                                                     *
* Nastepnie (rowniez jako Administrator) nalezy wykonac:              *
*                                                                     *
*   ppm repo up theory58S                                             *
*                                                                     *
* Ostatnie polecenie nalezy uruchamiac az do chwili ujrzenia na       *
* poczatku wyswietlanej listy tekstu "theory58S".                     *
EOT
    template_precompile   => "Kompilowanie szablonow... ",
    template_removal_failed => <<END,
OSTRZEZENIE: Nie mozna usunac katalogu '##datadir##/template'.
         Zostal on przeniesiony do '##datadir##/deleteme', ktory powinien zostac
         usuniety reczne, by zwolnic miejsce na dysku.
END
    template_removing_dir => "Usuwanie istniejacych skompilowanych szablonow... ",
    update_cf_invalid_name => 
        "Usuwanie pola dodatkowego '##field##', z powodu nieprawidlowej nazwy...",
    update_flags_bad_name => <<'END',
"##flag##" nie jest prawidlowa nazwa dla flagi. Nalezy zmienic nazwe na taka, ktora
nie zawiera spacji lub przecinkow.
END
    update_nomail_bad => <<'END',
OSTRZEZENIE: Nastepujacy uzytkownicy zostali okresleni w pliku ##data##/nomail, lecz
nie posiadaja konta w tej instalacji. Uzytkownicy ci zostali przeniesieni do pliku
##data##/nomail.bad:
END
    update_summary_truncate_comment => 
        "Krótki opis był dłuższy niż 255"
        . " znaków i został skrócony podczas aktualizacji."
        . " Pierwotna treść była następująca:\n\n##summary##",

		update_summary_truncated => <<'END',
OSTRZEZENIE: Krotkie opisy niektorych bledow byly dluzsze niz 255 znakow. Zostaly one
zapisane jako komentarze, a nastepnie skrocone do dlugosci 255 znakow. Dotyczy
to bledow:

END
    update_quips => <<'END',
Sentencje sa przechowywane w bazie danych zamiast w oddzielnym pliku.
Zawartosc pliku ##data##/comments zostala skopiowana do bazy danych, a
nazwa pliku zmieniona na ##data##/comments.bak. Po sprawdzeniu czy
sentencje zostaly skopiowane prawidlowo mozna usunac ten plik.
END
    update_queries_to_tags => "Tworzenie tabeli etykiet:",
    webdot_bad_htaccess => <<END,
OSTRZEZENIE: Brak dostepu do plikow graficznych zaleznosci. Usun plik ##dir##/.htaccess
i uruchom skrypt checksetup.pl.
END
);

1;
