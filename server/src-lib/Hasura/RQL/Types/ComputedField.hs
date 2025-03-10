-- |
-- Description: Schema cache types related to computed field
module Hasura.RQL.Types.ComputedField
  ( ComputedFieldDefinition (..),
    ComputedFieldFunction (..),
    ComputedFieldInfo (..),
    ComputedFieldName (..),
    ComputedFieldReturn (..),
    CustomFunctionNames (..),
    FunctionSessionArgument (..),
    FunctionTableArgument (..),
    FunctionTrackedAs (..),
    cfiDescription,
    cfiFunction,
    cfiName,
    cfiReturnType,
    cfiXComputedFieldInfo,
    computedFieldNameToText,
    fromComputedField,
    onlyScalarComputedFields,
    _CFRScalar,
    _CFRSetofTable,
  )
where

import Control.Lens hiding ((.=))
import Data.Aeson
import Data.Aeson.Casing
import Data.Sequence qualified as Seq
import Data.Text.Extended
import Data.Text.NonEmpty (NonEmptyText (..))
import Database.PG.Query qualified as Q
import Hasura.Backends.Postgres.SQL.Types hiding (FunctionName, TableName)
import Hasura.Incremental (Cacheable)
import Hasura.Prelude
import Hasura.RQL.Types.Backend
import Hasura.RQL.Types.Common
import Hasura.RQL.Types.Function
import Hasura.SQL.Backend
import Language.GraphQL.Draft.Syntax (Name)

newtype ComputedFieldName = ComputedFieldName {unComputedFieldName :: NonEmptyText}
  deriving (Show, Eq, Ord, NFData, FromJSON, ToJSON, ToJSONKey, Q.ToPrepArg, ToTxt, Hashable, Q.FromCol, Generic, Cacheable)

computedFieldNameToText :: ComputedFieldName -> Text
computedFieldNameToText = unNonEmptyText . unComputedFieldName

fromComputedField :: ComputedFieldName -> FieldName
fromComputedField = FieldName . computedFieldNameToText

data ComputedFieldDefinition b = ComputedFieldDefinition
  { _cfdFunction :: !(FunctionName b),
    _cfdTableArgument :: !(Maybe FunctionArgName),
    _cfdSessionArgument :: !(Maybe FunctionArgName)
  }
  deriving stock (Generic)

deriving instance (Backend b) => Show (ComputedFieldDefinition b)

deriving instance (Backend b) => Eq (ComputedFieldDefinition b)

instance (Backend b) => NFData (ComputedFieldDefinition b)

instance (Backend b) => Hashable (ComputedFieldDefinition b)

instance (Backend b) => Cacheable (ComputedFieldDefinition b)

instance (Backend b) => ToJSON (ComputedFieldDefinition b) where
  toJSON = genericToJSON hasuraJSON {omitNothingFields = True}

instance (Backend b) => FromJSON (ComputedFieldDefinition b) where
  parseJSON = genericParseJSON hasuraJSON {omitNothingFields = True}

-- | The function table argument is either the very first argument or the named
-- argument with an index. The index is 0 if the named argument is the first.
data FunctionTableArgument
  = FTAFirst
  | FTANamed
      !FunctionArgName
      -- ^ argument name
      !Int
      -- ^ argument index
  deriving (Show, Eq, Generic)

instance Cacheable FunctionTableArgument

instance NFData FunctionTableArgument

instance Hashable FunctionTableArgument

instance ToJSON FunctionTableArgument where
  toJSON FTAFirst = String "first_argument"
  toJSON (FTANamed argName _) = object ["name" .= argName]

-- | The session argument, which passes Hasura session variables to a
-- SQL function as a JSON object.
data FunctionSessionArgument
  = FunctionSessionArgument
      !FunctionArgName
      -- ^ The argument name
      !Int
      -- ^ The ordinal position in the function input parameters
  deriving (Show, Eq, Generic)

instance Cacheable FunctionSessionArgument

instance NFData FunctionSessionArgument

instance Hashable FunctionSessionArgument

instance ToJSON FunctionSessionArgument where
  toJSON (FunctionSessionArgument argName _) = toJSON argName

data FunctionTrackedAs (b :: BackendType)
  = FTAComputedField ComputedFieldName SourceName (TableName b)
  | FTACustomFunction CustomFunctionNames
  deriving (Generic)

-- | The function name and input arguments name for the "args" field parser.
--
-- > function_name(args: args_name)
data CustomFunctionNames = CustomFunctionNames
  { cfnFunctionName :: Name,
    cfnArgsName :: Name
  }
  deriving (Show, Eq, Generic)

deriving instance Backend b => Show (FunctionTrackedAs b)

deriving instance Backend b => Eq (FunctionTrackedAs b)

data ComputedFieldReturn (b :: BackendType)
  = CFRScalar !(ScalarType b)
  | CFRSetofTable !(TableName b)
  deriving (Generic)

deriving instance Backend b => Show (ComputedFieldReturn b)

deriving instance Backend b => Eq (ComputedFieldReturn b)

instance Backend b => Cacheable (ComputedFieldReturn b)

instance Backend b => NFData (ComputedFieldReturn b)

instance Backend b => Hashable (ComputedFieldReturn b)

instance Backend b => ToJSON (ComputedFieldReturn b) where
  toJSON =
    genericToJSON $
      defaultOptions
        { constructorTagModifier = snakeCase . drop 3,
          sumEncoding = TaggedObject "type" "info"
        }

$(makePrisms ''ComputedFieldReturn)

data ComputedFieldFunction (b :: BackendType) = ComputedFieldFunction
  { _cffName :: !(FunctionName b),
    _cffInputArgs :: !(Seq.Seq (FunctionArg b)),
    _cffTableArgument :: !FunctionTableArgument,
    _cffSessionArgument :: !(Maybe FunctionSessionArgument),
    _cffDescription :: !(Maybe PGDescription)
  }
  deriving (Show, Eq, Generic)

instance (Backend b) => Cacheable (ComputedFieldFunction b)

instance (Backend b) => NFData (ComputedFieldFunction b)

instance (Backend b) => Hashable (ComputedFieldFunction b)

instance (Backend b) => ToJSON (ComputedFieldFunction b) where
  toJSON = genericToJSON hasuraJSON

data ComputedFieldInfo (b :: BackendType) = ComputedFieldInfo
  { _cfiXComputedFieldInfo :: !(XComputedField b),
    _cfiName :: !ComputedFieldName,
    _cfiFunction :: !(ComputedFieldFunction b),
    _cfiReturnType :: !(ComputedFieldReturn b),
    _cfiDescription :: !(Maybe Text)
  }
  deriving (Generic)

deriving instance (Backend b) => Eq (ComputedFieldInfo b)

deriving instance (Backend b) => Show (ComputedFieldInfo b)

instance (Backend b) => NFData (ComputedFieldInfo b)

instance (Backend b) => Cacheable (ComputedFieldInfo b)

instance (Backend b) => Hashable (ComputedFieldInfo b)

instance (Backend b) => ToJSON (ComputedFieldInfo b) where
  -- spelling out the JSON instance in order to skip the Trees That Grow field
  toJSON (ComputedFieldInfo _ name func tp description) =
    object ["name" .= name, "function" .= func, "return_type" .= tp, "description" .= description]

$(makeLenses ''ComputedFieldInfo)

onlyScalarComputedFields :: [ComputedFieldInfo backend] -> [ComputedFieldInfo backend]
onlyScalarComputedFields = filter (has (cfiReturnType . _CFRScalar))
