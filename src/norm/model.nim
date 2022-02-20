import std/[macros, options, strutils, typetraits, strformat]

import private/dot
import pragmas


type
  Model* = ref object of RootObj
    ##[ Base type for models.

    ``id`` corresponds to row id in DB. **Updated automatically, do not update manually!**
    ]##

    id* {.pk, ro.}: int64


func isModel*[T: Model](val: T): bool = true

func isModel*[T: Model](val: Option[T]): bool = true

func isModel*[T](val: T): bool = false

func model*[T: Model](val: T): Option[T] = some val

func model*[T: Model](val: Option[T]): Option[T] = val

func model*[T](val: T): Option[Model] =
  ## This is never called and exists only to please the compiler.

  none Model

func table*(T: typedesc[Model]): string =
  ## Get table name for `Model <#Model>`_, which is the type name in single quotes.

  when T.hasCustomPragma(tableName):
    '"' & T.getCustomPragmaVal(tableName) & '"'
  else:
    '"' & $T & '"'

func col*(T: typedesc[Model], fld: string): string =
  ## Get column name for a `Model`_ field, which is just the field name.

  fld

func col*[T: Model](obj: T, fld: string): string =
  ## Get column name for a `Model`_ instance field.

  T.col(fld)

func fCol*(T: typedesc[Model], fld: string): string =
  ## Get fully qualified column name for a `Model`_ field: ``table.col``.

  "$#.$#" % [T.table, T.col(fld)]

func fCol*[T: Model](obj: T, fld: string): string =
  ## Get fully qualified column name for a `Model`_ instance field.

  T.fCol(fld)

func fCol*(T: typedesc[Model], fld, tAls: string): string =
  ## Get fully qualified column name with an alias instead of the actual table name: ``alias.col``.

  "$#.$#" % [tAls, T.col(fld)]

func fCol*[T: Model](obj: T, fld, tAls: string): string =
  ## Get fully qualified column name with an alias instead of the actual table name for a `Model`_ instance field.

  T.fCol(fld, tAls)

func cols*[T: Model](obj: T, force = false): seq[string] =
  ##[ Get columns for `Model`_ instance.

  If ``force`` is ``true``, fields with `ro <pragmas.html#ro.t>`_ are included.
  ]##

  for fld, val in obj[].fieldPairs:
    if force or not obj.dot(fld).hasCustomPragma(ro):
      result.add obj.col(fld)

func rfCols*[T: Model](obj: T, flds: seq[string] = @[]): seq[string] =
  ## Recursively get fully qualified column names for `Model`_ instance and its `Model`_ fields.

  for fld, val in obj[].fieldPairs:
    result.add if len(flds) == 0: obj.fCol(fld) else: obj.fCol(fld, """"$#"""" % flds.join("_"))

    if val.isModel and val.model.isSome:
      result.add (get val.model).rfCols(flds & fld)

func joinGroups*[T: Model](obj: T, flds: seq[string] = @[]): seq[tuple[tbl, tAls, lFld, rFld: string]] =
  ##[ For each `Model`_ field of `Model`_ instance, get:
  - table name for the field type
  - full column name for the field
  - full column name for ``id`` field of the field type

  Used to construct ``JOIN`` statements: ``JOIN {tbl} AS {tAls} ON {lFld} = {rFld}``
  ]##

  for fld, val in obj[].fieldPairs:
    if val.model.isSome:
      let
        subMod = get val.model
        tbl = typeof(subMod).table
        tAls = """"$#"""" % (flds & fld).join("_")
        ptAls = if len(flds) == 0: typeof(obj).table else: """"$#"""" % flds.join("_")
        lFld = obj.fCol(fld, ptAls)
        rFld = subMod.fCol("id", tAls)
        grp = (tbl: tbl, tAls: tAls, lFld: lFld, rFld: rFld)

      result.add grp & subMod.joinGroups(flds & fld)

proc checkRo*(T: typedesc[Model]) =
  ## Stop compilation if an object has `ro`_ pragma.

  when T.hasCustomPragma(ro):
    {.error: "can't use mutating procs with read-only models".}


proc getRelatedFieldNameTo*[M: Model](targetTableName: static string, normModel: typedesc[M]): string {.compileTime.} =
  ## A compile time proc that analyzes the given `normModel` type for any foreign key field that points to
  ## a table with the name of `targetTableName`. Raises a FieldDefect at compile time if the model does not
  ## have exactly one foreign key field to that table 
  var fieldNames: seq[string] = @[]
  const name = typetraits.name
  
  for sourceFieldName, sourceFieldValue in M()[].fieldPairs:
      #Handles case where field is an int64 with fk pragma
      when sourceFieldValue.hasCustomPragma(fk):
        when targetTableName == sourceFieldValue.getCustomPragmaVal(fk).table():
          fieldNames.add(sourceFieldName)
      
      #Handles case where field is a Model type
      elif sourceFieldValue is Model:
        when targetTableName == sourceFieldValue.type().table():
          fieldNames.add(sourceFieldName)
      
      #Handles case where field is a Option[Model] type
      elif sourceFieldValue is Option:
        when sourceFieldValue.get() is Model:
          when targetTableName == genericParams(sourceFieldValue.type()).get(0).table():
              fieldNames.add(sourceFieldName)

  if fieldNames.len() == 1:
    return fieldNames[0]
  
  elif fieldnames.len() < 1:
    let errorMsg = fmt "Tried getting foreign key field from model '{name(M)}' to model '{targetTableName}' but there is no such field!"
    raise newException(FieldDefect, errorMsg)
  
  elif fieldnames.len() > 1:
    let errorMsg = fmt "Can't infer foreign key field from model '{name(M)}' to model '{targetTableName}'! There is more than one foreign key field to that table!"
    raise newException(FieldDefect, errorMsg)


proc getRelatedFieldNameTo*[S: Model, T:Model](source: typedesc[S], target: typedesc[T]): string {.compileTime.} =
  ## A compile time proc that analyzes the given `source` model for any foreign key field that points to
  ## the table of the `target` model. Raises a FieldDefect at compile time if the model does not
  ## have exactly one foreign key field to that table 
  result = getRelatedFieldNameTo(T.table(), source)
