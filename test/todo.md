
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
  -m tar bort filen
  -0 läggar bara till ingen komprimering
  
När alla *.asc filerna är slut.
Ta en checksumma på trans.zip
  splitta trans.zip i lagom stora chuml (MAX)
  split --verbose --suffix=4 --bytes=MAX --numeric-suffixes trans.zip trans.zip.-part.
  
för varje part fil
  skicka över en partfil
  vänta tills den är borta
  börja om
  
  
