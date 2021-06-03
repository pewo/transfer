
# TODO

Lågsida: enkelt alternativ

Lista alla filer *.asc
Kontrollera checksummor
summera strolek på varje bundle
  bör kunna hantera om en bundle är större än MAX
  splitta stor bundle till mindre block
summera storlek på alla bundle
när den totala storleken är större än MAX
Flytta filer till transfer
Skapa en translog fil och flytta den till transfer

Vänta tills transferloggen är borta
Börja om

Lågsida: annat alternativ
Lista alla filer *.asc
Kontrollera checksummor
lägg till *.asc och och datafiler i ett ziparkiv
zip -m0 trans.zip <filer>
  -j junk (dont record direcotries)
  -m tar bort filen
  -0 läggar bara till ingen komprimering
  
När alla *.asc filerna är slut.
  splitta trans.zip i lagom stora chuml (MAX)
  split --verbose --suffix=4 --bytes=MAX --numeric-suffixes trans.zip trans.zip.-part.
  
för alla poart filer
  skapa en checksumma som går att verifiera med "sha256sum --check"
  
för varje part fil
  skicka över en partfil
  vänta tills den är borta
  
När alla filerna är överflyttade och borta
  Skicka över sha256sum checkfilen.
  

Högsida
  vänta tills det finns en sha256sum checkfil *.asc
  kontrollera alla checksummor, om något saknas hoppa tills nästa checksumfil
  
  När hela checksumfilen och dessa data stämmer.
  för varje datafil
    lägg till den till trans.zip
    ta bort datafilen
  
  verifiera trans.zip
  zip -v -T trans.zip
  om rc=0 
  packa upp trans.zip på destinationkatalogen
  unzip -jnd /tmp/zip2... trans.zip
   -n never overwrite
   -d destination direxctory
   -j no directory
  
  ta bort trans.zip
  
  
  
  
