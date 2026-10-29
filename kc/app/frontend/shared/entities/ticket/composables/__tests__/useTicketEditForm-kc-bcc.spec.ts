// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// KC: the BCC field must live in the article group right after CC, so its value is submitted as
//  article.bcc (useTicketEdit) instead of ending up among the ticket attributes.

import { computed, defineComponent, ref } from 'vue'

import renderComponent from '#tests/support/components/renderComponent.ts'

import { createDummyTicket } from '#shared/entities/ticket-article/__tests__/mocks/ticket.ts'

import { useTicketEditForm } from '../useTicketEditForm.ts'

type SchemaNode = { name?: string; children?: unknown }

const collectNames = (node: unknown, names: string[] = []): string[] => {
  if (!node || typeof node !== 'object') return names
  const { name, children } = node as SchemaNode
  if (name) names.push(name)
  if (Array.isArray(children)) children.forEach((child) => collectNames(child, names))
  return names
}

const getSchemas = () => {
  let schemas: { ticketSchema: unknown; articleSchema: unknown } | undefined

  renderComponent(
    defineComponent({
      setup() {
        const { ticketSchema, articleSchema } = useTicketEditForm(
          computed(() => createDummyTicket()),
          ref(),
        )
        schemas = { ticketSchema, articleSchema }
        return () => null
      },
    }),
  )

  return schemas!
}

describe('useTicketEditForm (KC BCC)', () => {
  it('places BCC in the article group directly after CC', () => {
    const { articleSchema } = getSchemas()
    const names = collectNames(articleSchema)

    expect(names[0]).toBe('article')
    expect(names).toContain('bcc')
    expect(names.indexOf('bcc')).toBe(names.indexOf('cc') + 1)
  })

  it('keeps BCC out of the ticket attribute group', () => {
    const { ticketSchema } = getSchemas()

    expect(collectNames(ticketSchema)).not.toContain('bcc')
  })
})
