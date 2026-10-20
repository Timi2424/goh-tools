;/*=====================================================================
;// sondy.inc - gotowe bloki, ktore zmuszaja silnik do potwierdzenia
;//
;// To NIE jest plik do dolaczenia. To katalog blokow do wklejenia.
;// Kazdy ma: co dowodzi, gdzie go wkleic i czego szukac.
;//
;// POWOD ISTNIENIA: szesc przebiegow testowych poszlo na debugowanie
;// zachowania w pliku, ktorego gra w ogole nie czytala. Cisza w logu nie
;// odroznia sukcesu od porazki - udany spawn, emit i przypisanie wlasciciela
;// nie loguja niczego.
;//
;// ZASADA NR 1: sonda nie moze zalezec od badanej rzeczy.
;//   Dwa nasze beacony mialy selektor {tag c47_d}. Gdy tag nie lapal,
;//   milczaly - i nie dowodzily niczego. Jesli badasz tag, sonda nie moze
;//   go uzywac. Jesli badasz samolot, sonda nie moze go selekcjonowac.
;//
;// ZASADA NR 2: najpierw udowodnij, ze kod dociera do silnika.
;//   Dopiero potem debuguj, dlaczego robi nie to, co chcesz.
;//
;// Wszystkie konstrukcje ponizej pochodza z prawdziwych plikow gry albo
;// Hortena. Nazwa z binarki nie jest dowodem na dopuszczalna skladnie.
;//=====================================================================*/


;/*---------------------------------------------------------------------
;// SONDA 1: CZY TEN PLIK W OGOLE ZYJE?            (czas parsowania)
;//
;// Najtansza i najmocniejsza sonda, jaka mamy. Dowolny nieznany klucz
;// w pliku danych wywala wczytywanie i silnik wypisuje SCIEZKE LADOWANIA,
;// PLIK, NUMER LINII i sam token oznaczony znakiem <<.
;//
;// Gdzie: byle gdzie w badanym .def / .ext / .inc
;// Szukaj w logu: "unexpected token (eResource.cpp:102)"
;//                albo "(eInteractionEntityInfo.cpp:66)"
;// Odczyt: komunikat jest = plik zyje. Brak komunikatu = plik MARTWY.
;//
;// UWAGA: to celowo wywala wczytywanie. Usun po odczycie.
;//-------------------------------------------------------------------*/

	{HF_SONDA_CZY_TEN_PLIK_ZYJE 1}


;/*---------------------------------------------------------------------
;// SONDA 2: CZY TRIGGER SIE ODPALIL?              (czas gry, ekran)
;//
;// Zegar na HUD. Widac natychmiast, bez czytania logu, bez pauzowania.
;// Warunek pusty = odpala sie raz, od razu po starcie misji.
;//
;// Gdzie: lista {triggers} w .mi albo dcg_script.inc
;// Odczyt: pojawil sie zegar = trigger dziala.
;//
;// Skladnia z prawdziwego uzycia: detect_errors.mi, HF-dcg_script.inc:30
;//-------------------------------------------------------------------*/

	{"hf_sonda/trigger_zyje"
		{condition
		}
		{actions
			{"timer"
				{time 999}
				{title "hf_sonda_trigger"}
			}
		}
	}


;/*---------------------------------------------------------------------
;// SONDA 3: CZY TRIGGER SIE ODPALIL?              (czas gry, log)
;//
;// Gdy zegar przeszkadza albo chcesz slad w logu zamiast na ekranie.
;// Nieistniejacy numer waypointa daje wpis w logu.
;//
;// Selektor CELOWO {tag _user} - to tag, ktory w konkwiscie ma kazda
;// jednostka gracza, wiec sonda nie zalezy od niczego, co badasz.
;//
;// Gdzie: {actions} badanego triggera
;// Szukaj w logu: "Waypoint 999999 not found"
;//-------------------------------------------------------------------*/

	{"waypoint"
		{who
			{type actor}
			{actors
				{ignore_captured_by_user 0}
				{tag _user}
			}
		}
		{action
			{type start}
			{waypoint "999999"}
		}
	}


;/*---------------------------------------------------------------------
;// SONDA 4: ODCZYTAJ LICZBE Z GRY                 (czas gry, ekran)
;//
;// Zegar pokazuje liczbe, wiec moze SLUZYC ZA WYSWIETLACZ. Switch po
;// wariantach, w kazdym inna liczba - jeden przebieg zwraca wartosc,
;// a nie jeden bit.
;//
;// Ponizej: odczyt NUMERU WLASCICIELA encji. Klauzula {player "N"}
;// w selektorze jest udokumentowana w podreczniku edytora misji
;// ("entities of the indicated player only are selected") i uzywana
;// naprawde w multi.pak -> fr-kharkov/frontlines.mi:9589.
;//
;// Gdzie: lista {triggers}
;// Odczyt: zegar 11 = gracz 1, 22 = gracz 2, ... 99 = niczyj.
;//
;// Dla drugiej encji w tym samym przebiegu uzyj innych liczb (110, 120...),
;// zeby obie odpowiedzi dalo sie rozroznic na jednym ekranie.
;//-------------------------------------------------------------------*/

	{"hf_sonda/czyje_to"
		{condition
			{terms
				{"1.entities"
					{selector
						{ignore_captured_by_user 0}
						{tag BADANY_TAG}
					}
				}
			}
		}
		{actions
			{"switch"
				{"case"
					{condition
						{type entities}
						{selector
							{ignore_captured_by_user 0}
							{tag BADANY_TAG}
							{player "1"}
						}
					}
					{"timer" {time 11} {title "hf_sonda_wlasciciel"}}
				}
				{"case"
					{condition
						{type entities}
						{selector
							{ignore_captured_by_user 0}
							{tag BADANY_TAG}
							{player "2"}
						}
					}
					{"timer" {time 22} {title "hf_sonda_wlasciciel"}}
				}
				{"case"
					{condition
						{type entities}
						{selector
							{ignore_captured_by_user 0}
							{tag BADANY_TAG}
							{player "3"}
						}
					}
					{"timer" {time 33} {title "hf_sonda_wlasciciel"}}
				}
				{"case"
					{condition
						{type entities}
						{selector
							{ignore_captured_by_user 0}
							{tag BADANY_TAG}
							{player "4"}
						}
					}
					{"timer" {time 44} {title "hf_sonda_wlasciciel"}}
				}
				{"default"
					{"timer" {time 99} {title "hf_sonda_wlasciciel"}}
				}
			}
		}
	}


;/*---------------------------------------------------------------------
;// SONDA 5: CZY SELEKTOR COKOLWIEK LAPIE?         (czas gry, ekran)
;//
;// Zanim uwierzysz, ze akcja nie dziala, sprawdz, czy selektor trafia.
;// {"delete"} jest brutalne, ale jednoznaczne: jesli encja znika,
;// selektor lapal ja na pewno. Tak ustalilismy, ze {"emit"} nie dziala
;// NIE z powodu selektora.
;//
;// Gdzie: {actions}, zamiast badanej akcji
;// Odczyt: encja zniknela = selektor dobry, wina lezy w akcji.
;//-------------------------------------------------------------------*/

	{"delete"
		{selector
			{ignore_captured_by_user 0}
			{tag BADANY_TAG}
			{type vehicle}
		}
	}


;/*---------------------------------------------------------------------
;// SONDA 6: CZY SKRYPT ENCJI DOSZEDL DO TEGO MIEJSCA?
;//
;// Kontekst skryptu encji (.inc, blok {on ...}) - tu nie ma triggerow
;// ani zegara. Nieistniejaca kosc daje wpis w logu.
;//
;// Gdzie: wewnatrz {on "nazwa"} w set/interaction_entity/*.inc
;// Szukaj w logu: "Bone HF_SONDA not found in"
;//
;// Zaleta nad celowym bledem skladni: NIE wywala wczytywania, wiec
;// test idzie dalej i widac, co dzieje sie potem.
;//-------------------------------------------------------------------*/

	{spawn "dummy" "HF_SONDA_KOSC"}


;/*---------------------------------------------------------------------
;// CZEGO SONDA NIE ZROBI
;//
;// "Remap actor_id" leci WYLACZNIE przy wczytywaniu mapy. Wszystko, co
;// dzieje sie w trakcie bitwy, jest w logu niewidoczne, dopoki sam nie
;// wymusisz komunikatu.
;//
;// Dlatego kazda zmiana musi albo dawac efekt widoczny dla gracza, albo
;// miec wpieta sonde. Trzecia mozliwosc - "zobaczymy, czy zadzialalo" -
;// kosztowala nas wiecej niz wszystkie pozostale bledy razem.
;//-------------------------------------------------------------------*/
