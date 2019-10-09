rm -rf newSwagger
mkdir newSwagger
cd newSwagger
mkdir generatedModels
mkdir generatedControls
echo "Загрузка api.json"
curl -s http://retail-tst.payment.ru/api/swagger/docs/v1 > api.json &
wait
echo "Загрузка генератора"
curl -s https://raw.githubusercontent.com/kekcik/PSBCodeGen/master/main.js > main.js &
wait
echo "Загрузка негенерирумеых файлов"
curl -s https://raw.githubusercontent.com/kekcik/PSBCodeGen/master/PSBCodeGen.swift > PSBCodeGen.swift &
wait
echo "Генерация методов"
node main.js
rm -rf main.js
rm -rf api.json
cd ..
echo "Done :)"
