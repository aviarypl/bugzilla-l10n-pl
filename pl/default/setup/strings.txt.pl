# 3.4.7PL@aviary.pl 
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Initial Developer of the Original Code is Everything Solved.
# Portions created by Everything Solved are Copyright (C) 2007
# Everything Solved. All Rights Reserved.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# Contributor(s): Max Kanat-Alexander <mkanat@bugzilla.org>
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
    blacklisted => 'zablokowana',
    checking_for => 'Sprawdzanie',
    checking_dbd      => 'Sprawdzanie dostepnych modulow Perl DBD...',
    checking_optional => 'Nastepujace moduly Perla sa opcjonalne:',
    checking_modules  => 'Sprawdzanie modulow Perl...',
    commands_dbd      => <<EOT,
NALEZY URUCHOMIC JEDNO Z NASTEPUJACYCH POLECEN (w zaleznosci od uzywanej bazy danych):
EOT
    commands_optional => 'POLECENIA DO ZAINSTALOWANIA OPCJONALNYCH MODULOW:',
    commands_required => <<EOT,
POLECENIA DO ZAINSTALOWANIA WYMAGANYCH MODULOW (*Musisz* uruchomic wszystkie te polecenia
i nastepnie ponownie uruchomic skrypt checksetup.pl):
EOT
    done => 'zakonczono.',
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
zostaly wyswietlone ponizej w nastepujacej kolejnosci: najpierw dla kolumny ##id_column## i nastepnie
dla kolumny wymagajacej naprawienia ##column##:

EOT
    install_module => 'Instalowanie modulu ##module## wersja ##version##...',
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
    modules_message_db => <<EOT,
***********************************************************************
* DOSTEP DO BAZY DANYCH                                               *
***********************************************************************
* Aby uzyskac dostep do twojej bazy danych Bugzilla wymaga, aby       *
* dla uruchomionej bazy byl prawidlowo zainstalowany modul "DBD".     *
* Zobacz ponizej poprawne polecenia do uruchomienia instalacji modulu *
* odpowiedniego dla twojej bazy danych.                               *
EOT
    modules_message_optional => <<EOT,
***********************************************************************
* OPCJONALNE MODULY                                                   *
***********************************************************************
* Niektore moduly Perla nie sa wymagane do prawidlowego dzialania     *
* Bugzilli, ale instalujac najnowsza wersje uzyskasz dostep do        *
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
    template_removing_dir => "Usuwanie istniejacych skompilowanych szablonow... ",
);

1;
