module Qwen.GLSL
  ( module GLSL,
    Shader (..),
    int,
    uint,
    float,
    var,
    field,
    call,
    construct,
    array,
    arrayAt,
    declaration,
    local,
    set,
    function,
    ifThen,
    constant,
    constantArray,
    samplerName,
    sampler,
    samplerUniform,
    samplerUniforms,
    validateBindings,
    renderUnit,
    renderShader,
    parseUnit,
    parseBody,
    parseShader,
  )
where

import Data.Bifunctor (first)
import Data.List (isPrefixOf)
import Data.Set qualified as Set
import Language.GLSL.Parser qualified as Parser
import Language.GLSL.Pretty ()
import Language.GLSL.Syntax as GLSL
import Text.PrettyPrint.HughesPJClass (prettyShow)

-- Minecraft resolves namespaced includes before compiling GLSL. Keep these
-- resource references outside the language library's preprocessed AST.
data Shader = Shader [String] TranslationUnit deriving (Eq, Show)

int :: Int -> Expr
int n
  | n < 0 = UnaryNegate (IntConstant Decimal (negate (toInteger n)))
  | otherwise = IntConstant Decimal (toInteger n)

uint :: (Integral a) => a -> Expr
uint n
  | n < 0 || toInteger n > 4294967295 = error "GLSL uint literal exceeds 32 bits"
  | otherwise = UIntConstant Decimal (toInteger n)

float :: Float -> Expr
float n
  | isNaN n || isInfinite n = error "GLSL float literal must be finite"
  | n < 0 = UnaryNegate (FloatConstant SinglePrecision (show (negate n)))
  | otherwise = FloatConstant SinglePrecision (show n)

var :: String -> Expr
var = Variable

field :: String -> String -> Expr
field name = FieldSelection (var name)

call :: String -> [Expr] -> Expr
call name = FunctionCall (FuncIdExpr (var name)) . Params

typeSpec :: BuiltinType -> TypeSpecifier
typeSpec ty = TypeSpec (Builtin ty) []

construct :: BuiltinType -> [Expr] -> Expr
construct ty = FunctionCall (FuncIdTypeSpec (typeSpec ty)) . Params

array :: BuiltinType -> [Expr] -> Expr
array ty = FunctionCall (FuncIdTypeSpec (TypeSpec (Builtin ty) [Unsized])) . Params

arrayAt :: BuiltinType -> [Expr] -> Expr -> Expr
arrayAt ty xs = Bracket (array ty xs)

declaration :: [TypeQualifier] -> BuiltinType -> [(String, Maybe Expr)] -> Declaration
declaration qualifiers ty values =
  InitDeclaration
    (FullType qualifiers (typeSpec ty))
    [InitDecl (Declarator name []) value | (name, value) <- values]

local :: BuiltinType -> String -> Expr -> Statement
local ty name value = DeclarationStatement (declaration [] ty [(name, Just value)])

set :: Expr -> Expr -> Statement
set target value = ExpressionStatement (Just (Binary Equal target value))

function :: BuiltinType -> String -> [(BuiltinType, String)] -> [Statement] -> ExternalDeclaration
function ty name parameters body =
  FunctionDefinition
    ( FuncProt
        (FullType [] (typeSpec ty))
        name
        [ParameterDeclaration [] (typeSpec t) (Just (Declarator n [])) | (t, n) <- parameters]
    )
    (Compound body)

ifThen :: Expr -> [Statement] -> Statement
ifThen condition yes = SelectionStatement condition (CompoundStatement (Compound yes)) Nothing

constant :: BuiltinType -> String -> Expr -> ExternalDeclaration
constant ty name value = Declaration (declaration [TypeQualSto Const] ty [(name, Just value)])

constantArray :: BuiltinType -> String -> [Expr] -> ExternalDeclaration
constantArray ty name values =
  Declaration
    ( InitDeclaration
        (FullType [TypeQualSto Const] (typeSpec ty))
        [InitDecl (Declarator name [Sized (int (length values))]) (Just (array ty values))]
    )

-- Post-effect JSON uses logical names; Minecraft appends Sampler for GLSL.
samplerName :: String -> String
samplerName name = name ++ "Sampler"

sampler :: String -> Expr
sampler = var . samplerName

samplerUniform :: String -> ExternalDeclaration
samplerUniform name = Declaration (declaration [TypeQualSto Uniform] Sampler2D [(samplerName name, Nothing)])

samplerUniforms :: TranslationUnit -> [String]
samplerUniforms (TranslationUnit declarations) =
  [ name
  | Declaration (InitDeclaration (FullType qs (TypeSpec (Builtin Sampler2D) [])) ds) <- declarations,
    TypeQualSto Uniform `elem` qs,
    InitDecl (Declarator name _) _ <- ds
  ]

validateBindings :: [String] -> [TranslationUnit] -> Either String ()
validateBindings logical programs
  | length logical /= Set.size (Set.fromList logical) = Left "Duplicate post-effect sampler binding"
  | actual == expected = Right ()
  | otherwise =
      Left
        ( "Sampler interface mismatch: unbound="
            ++ show (actual Set.\\ expected)
            ++ ", undeclared="
            ++ show (expected Set.\\ actual)
        )
  where
    expected = Set.fromList (map samplerName logical)
    actual = Set.fromList (concatMap samplerUniforms programs)

renderUnit :: TranslationUnit -> String
renderUnit unit = prettyShow unit ++ "\n"

renderShader :: Shader -> String
renderShader (Shader includes unit) =
  renderUnit
    ( TranslationUnit
        [ PreprocessorDirective (VersionDirective 330 Nothing),
          PreprocessorDirective (ExtensionDirective "GL_ARB_separate_shader_objects" ExtensionRequire)
        ]
    )
    ++ unlines ["#include <" ++ resource ++ ">" | resource <- includes]
    ++ renderUnit unit

parseUnit :: FilePath -> String -> Either String TranslationUnit
parseUnit path = first show . Parser.parseNamed path

-- Operator files are statement blocks. The fixed function supplies the parser
-- context; every generated statement is subsequently assembled as an AST node.
parseBody :: FilePath -> String -> Either String [Statement]
parseBody path source = do
  TranslationUnit declarations <- parseUnit path ("void main() {\n" ++ source ++ "\n}")
  case declarations of
    [FunctionDefinition _ (Compound statements)] -> Right statements
    _ -> Left (path ++ ": expected one operator body")

-- Interface inspection leaves include expansion to Minecraft. Other directives
-- are still parsed, so unsupported preprocessing fails instead of being erased.
parseShader :: FilePath -> String -> Either String TranslationUnit
parseShader path = parseUnit path . unlines . map includeLine . lines
  where
    includeLine line
      | ["#include", resource] <- words line,
        "<" `isPrefixOf` resource,
        last resource == '>' =
          ""
      | otherwise = line
