// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

// It provides possibleTypes for union and interface types,
// which Apollo Client needs to properly handle inline fragments.
import introspection from '../../../../graphql/graphql_introspection.json'

interface IntrospectionType {
  kind: string
  name: string
  possibleTypes?: Array<{ name: string }>
}

interface IntrospectionData {
  data: {
    __schema: {
      types: IntrospectionType[]
    }
  }
}

const generatePossibleTypes = () => {
  const { types } = (introspection as IntrospectionData).data.__schema
  const possibleTypes: Record<string, string[]> = {}

  types.forEach((type) => {
    if (type.kind === 'UNION' || type.kind === 'INTERFACE') {
      possibleTypes[type.name] = type.possibleTypes?.map((t) => t.name) || []
    }
  })

  return possibleTypes
}

export default generatePossibleTypes()
