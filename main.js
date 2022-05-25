'use strict';

const fs = require('fs');

let rawdata = fs.readFileSync('api.json');
let apiDocs = JSON.parse(rawdata);

let typeDictionary = {
    'integer_undefined': 'Int',
    'string_undefined': 'String',
    'boolean_undefined': 'Bool',
    'number_double': 'Decimal',
    'string_date-time': 'Date',
    'integer_int32': 'Int',
    'integer_int64': 'Int64',
    'string_byte': 'Data',
    'string_uuid': 'String',
    'object_undefined': 'CAObject',
    'number_float': 'Decimal'
}
let defaultValueDictionary = {
    'Decimal': '0',
    'Int': '0',
    'Int64': '0',
    'String': '\"\"',
    'Bool': 'false',
}

let simpleTypes = ['Int', 'String', 'Double', 'Date', 'Data']
var pathGroups = {};
let customNames = {
    'class': 'aClass',
    'default': 'aDefault'
};
for (let key in apiDocs.definitions) {
    let definition = apiDocs.definitions[key];
    parseObject(key);
}

// parsePath(apiDocs.paths["/survey/getRatingSettings"], "/survey/getRatingSettings")

for (let key in apiDocs.paths) {
    parsePath(apiDocs.paths[key], key)
}
Object.keys(pathGroups).forEach(name => {
    printPath(name)
});

var text = "";
var properties = [];
var enums = [];

function saveText(nextPart) {
    text += (nextPart || '') + '\n';
}

function parsePath(data, address) {
    var pathObject = {};
    for (let key in data) {
        pathObject = data[key];
        // console.log(pathObject);
        pathObject.type = key;
        pathObject.path = address;
        pathObject.incomeTypes = [];
        let type = getTypeName(pathObject.responses['200'].schema);
        pathObject.dataType = type;
        let pathParts = pathObject.path.split('/');

        (pathObject.parameters || []).forEach(param => {
            let incomeType = getTypeName(param);
            let incomeTypeObject = {
                name: param.name,
                in: param.in,
                type: '',
                limitEnum: [],
                description: param.description || ''
            }
            if (param.enum != undefined) {
                incomeTypeObject.type = 'Int';
                incomeTypeObject.limitEnum = param.enum;
            } else if (param.schema != undefined && param.schema.enum != undefined) {
                incomeTypeObject.type = 'Int';
                incomeTypeObject.limitEnum = param.schema.enum;
            } else if (incomeType.typeName == undefined || incomeType.typeName == '_____') {
                incomeType = getTypeName(param.schema);
                incomeTypeObject.type = incomeType.typeName;
            } else {
                incomeTypeObject.type = incomeType.typeName;
            }
            pathObject.incomeTypes.push(incomeTypeObject);
        });
        if (pathGroups[pathParts[1]] == undefined) {
            pathGroups[pathParts[1]] = [];
        }
        pathGroups[pathParts[1]].push(pathObject);
    }
}

function parseQueryEnum() {

}

function printPath(name) {
    text = "";
    saveText("import Foundation\n")
    let className = firstToUpperCase(name) + "Api"
    saveText("public class " + className + " {");
    saveText("    public static let shared = " + className + "()\n");

    pathGroups[name].forEach(path => {

        let pathParts = path.path.split('/');
        pathParts = pathParts.slice(2);
        pathParts = pathParts.map(item => item.charAt(0) == '{' ? item.slice(1, -1) : item.replace("-", "_"))
        // pathParts = pathParts.filter(item => item.charAt(0) != '{')
        let comment = (path.summary || "").replace(/\r?\n/g, "").trim().replace(/psb/ig, "bnk");
        if (comment.length > 0) {
            saveText("    /// " + comment);
        }
        saveText("    public func " + path.type + pathParts.map(part => firstToUpperCase(part)).join("") + "(");
        path.incomeTypes.forEach(type => {
            // console.log(type.in + " " + type.type);
            let parts = type.name.split('.')
            let defaultValue = defaultValueDictionary[type.type]
            let defaultValueString = "? = nil"
            let commentString = ""
            if (defaultValue != undefined && type.in == 'path') {
                defaultValueString = " = " + defaultValue
            }
            let rawComment = type.description.replace(/\r?\n/g, "").replace(/psb/ig, "bnk")
            if (rawComment.length != 0) {
                commentString = ", // " + rawComment
            } else {
                commentString = ","
            }
            saveText("        " + parts[parts.length - 1] + ': ' + type.type + defaultValueString + commentString)
        })
        saveText("        mock: String? = nil,")
        let outcomeType = path.dataType.isEnum ? 'Int' : path.dataType.typeName;
        saveText("        callback: @escaping (Result<" + outcomeType + ">) -> Void");
        saveText("    ) {")

        let inQueryArgs = path.incomeTypes.filter(item => item.in == 'query' );
        let queryPartUrl = ""
        if (inQueryArgs && inQueryArgs.length > 0) {
            saveText("        var queryArgs = [String: Any]()")
            inQueryArgs.forEach(arg => {
                let parts = arg.name.split('.')
                let name = parts[parts.length - 1]
                let addsPart = ""
                if (arg.type == 'Date') {
                    addsPart = "?.toCommonApiFormat()"
                }
                saveText("        queryArgs[\"" + name + "\"] = " + name + addsPart)
            })
            saveText("        let argsString = queryArgs.map({ \"\\($0)=\\($1)\" }).joined(separator: \"&\")")
            queryPartUrl = ' + (argsString.isEmpty ? "" : "?\\(argsString)")'
            saveText("")
        }

        let pathPartsUrl = path.path.split('/');
        pathPartsUrl = pathPartsUrl.map(item => item.replace('{','\\(').replace('}',')') ).join("/");

        let bodyParam = path.incomeTypes.find(item => item.in == 'body')
        var bodyPart = ""
        if (bodyParam != undefined) {
            let parts = bodyParam.name.split('.')
            let name = parts[parts.length - 1]
            bodyPart = ", body: " + name
        }
        saveText("        let url = \"" + pathPartsUrl + '"' + queryPartUrl);
        saveText("        CommonApi.shared.request(url, method: ." + path.type + bodyPart + ", callback: callback, type: " + outcomeType + ".self, mock: mock)")
        saveText("    }\n")
    });
    saveText("}");
    fs.writeFile('Api/' + className + '.swift', text.trim(), function() {});
}

// parseObject(process.argv[2]);
function parseObject(className) {
    text = "";
    properties = [];
    enums = [];
    let obj = apiDocs.definitions[className];
    // console.log(obj);
    // let filedNames = Object.keys(obj.properties);
    // while (true) {}
    let requiredProps = obj.required || []
    // console.log(requiredProps);
    for (let propertyKey in obj.properties) {
        let property = obj.properties[propertyKey];
        let description = property.description;
        let type = getTypeName(property, className, propertyKey);
        let name = mapName(propertyKey)
        properties.push({
            description: description,
            name: mapName(propertyKey),
            type: type.typeName,
            isEnum: type.isEnum,
            isRequired: requiredProps.includes(name)
        });
        // requiredProps.length > 0 && console.log(requiredProps.includes(name));
    };
    printObject(className)
    fs.writeFile('Model/' + className + '.swift', text.trim() + "\n", function() {});
}

function mapName(name) {
    if (customNames[name] != undefined) {
        return customNames[name]
    } else {
        return name
    }
}

function printObject(className) {
    saveText('import Foundation\n\npublic class CA' + className + ': Codable {');

    for (let key in properties) {
        let property = properties[key];
        let comment = (property.description || "").replace(/\r?\n/g, "").trim().replace(/psb/ig, "bnk");
        if (comment.length > 0) {
            saveText("    /// " + comment);
        }
        let type = property.type;
        if (property.isEnum) {
            type += 'Enum'
            saveText("    public var " + property.name + "Value: CA" + type + "?" + " {");
            saveText("        return CA" + type + "(rawValue: " + property.name + " ?? 0)");
            saveText("    }");
            saveText("    private let " + property.name + ": Int" + (property.isRequired ? "" : "?"));
        } else {
            saveText("    public let " + property.name + ": " + type + (property.isRequired ? "" : "?"));
        }
        saveText();
    };

    saveText('    public init(');
    let params = ''
    for (let key in properties) {
        let property = properties[key];
        let type = property.type;
        if (property.isEnum) {
            type = 'Int'
        }
        params += "        " + property.name + ": " + type + (property.isRequired ? ",\n" : "? = nil,\n")
    };
    params = params.slice(0, -2);
    saveText(params)
    saveText('    ) {');

    for (let key in properties) {
        let property = properties[key];
        saveText("        self." + property.name + " = " + property.name);
    };
    saveText('    }');

    saveText('}');
    saveText();
    for (let key in enums) {
        let aEnum = enums[key];
        saveText('public enum CA' + aEnum.name + 'Enum: Int, Codable {');
        aEnum.fields.forEach(element => saveText('    case ' + element.name.trim().replace(/psb/ig, "bnk") + ' = ' + element.value));
        saveText('}');    
        saveText();
    };
}

function firstToUpperCase(string) {
    if (string == undefined || string.length == 0) {
        return ''
    }
    return string.charAt(0).toUpperCase() + string.slice(1);
}

function firstToLowerCase(string) {
    if (string == undefined || string.length == 0) {
        return ''
    }
    return string.charAt(0).toLowerCase() + string.slice(1);
}

function getTypeName(property, key, propertyKey) {
    let name = key + firstToUpperCase(propertyKey);
    if (property.enum != undefined) {
        property.isEnum = true
        let aEnum = {
            name: name,
            fields: []
        }
        if (property.description == undefined) {
            for (let key in property.enum) {
                let curCase = property.enum[key];
                aEnum.fields.push({
                    name: 'el' + curCase,
                    value: curCase
                });
            };
        } else {
            let parts = property.description.split('(');
            let enumParts = parts[parts.length - 1].split(')')[0].split(' , ');

            for (let partId in enumParts) {
                let part = enumParts[partId];
                let splittedPart = part.split(' = ')
                aEnum.fields.push({
                    name: mapName(firstToLowerCase(splittedPart[1])),
                    value: splittedPart[0]
                });
            };
        };
        enums.push(aEnum);
        return {
            typeName: name,
            isEnum: true
        }
    };
    if (property.type == 'array') {
        let result = getTypeName(property.items, key, propertyKey)
        let type = result.typeName;
        if (result.isEnum) {
            type = 'CA' + type + 'Enum'
        }
        return {
            typeName: '[' + type + ']',
            isEnum: false
        }
    };
    if (property['$ref'] != undefined) {
        let elem = property['$ref'].split('/')
        return {
            typeName: 'CA' + elem[elem.length - 1],
            isEnum: false
        }
    };
    let type = typeDictionary[property.type + '_' + property.format] || '_____';
    return {
        typeName: type,
        isEnum: false
    }
}
