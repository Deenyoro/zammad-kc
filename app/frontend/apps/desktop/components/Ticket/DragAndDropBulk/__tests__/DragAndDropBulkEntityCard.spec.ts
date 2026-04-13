// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { renderComponent } from '#tests/support/components/index.ts'

import DragAndDropBulkEntityCard, { type Props } from '../DragAndDropBulkEntityCard.vue'
import { DragAndDropBulkEntityType } from '../types.ts'

describe('DragAndDropBulkEntityCard', () => {
  const renderCard = (props: Props) => renderComponent(DragAndDropBulkEntityCard, { props })

  it('renders the label text', () => {
    const wrapper = renderCard({
      label: 'Run macro',
      entityType: DragAndDropBulkEntityType.Macro,
    })
    expect(wrapper.getByText('Run macro')).toBeInTheDocument()
  })

  describe('macro entity type', () => {
    it('renders the play-circle icon', () => {
      const wrapper = renderCard({
        label: 'Run macro',
        entityType: DragAndDropBulkEntityType.Macro,
      })
      expect(wrapper.getByIconName('play-circle')).toBeInTheDocument()
    })

    it('applies a yellow background to the icon container', () => {
      const wrapper = renderCard({
        label: 'Run macro',
        entityType: DragAndDropBulkEntityType.Macro,
      })
      expect(wrapper.html()).toContain('bg-yellow-300')
    })

    it('does not render the go-inside-group section', () => {
      const wrapper = renderCard({
        label: 'Run macro',
        entityType: DragAndDropBulkEntityType.Macro,
      })
      expect(wrapper.queryByIconName('arrow-down-short')).not.toBeInTheDocument()
    })
  })

  describe('ticket entity type', () => {
    it('renders the people-fill icon when no entity is provided', () => {
      const wrapper = renderCard({
        label: 'Assign tickets',
        entityType: DragAndDropBulkEntityType.Ticket,
      })
      expect(wrapper.getByIconName('people-fill')).toBeInTheDocument()
    })

    it('applies a green background to the icon container', () => {
      const wrapper = renderCard({
        label: 'Assign tickets',
        entityType: DragAndDropBulkEntityType.Ticket,
      })
      expect(wrapper.getByIconName('people-fill').parentElement).toHaveClass('bg-green-500')
    })

    it('renders the go-inside-group section when circle is false', () => {
      const wrapper = renderCard({
        label: 'Assign tickets',
        entityType: DragAndDropBulkEntityType.Ticket,
        circle: false,
      })
      expect(wrapper.getByIconName('arrow-down-short')).toBeInTheDocument()
    })

    it('does not render the go-inside-group section when circle is true', () => {
      const wrapper = renderCard({
        label: 'Assign tickets',
        entityType: DragAndDropBulkEntityType.Ticket,
        circle: true,
      })
      expect(wrapper.queryByIconName('arrow-down-short')).not.toBeInTheDocument()
    })
  })

  describe('circle prop', () => {
    it('applies rounded-full styling when true', () => {
      const wrapper = renderCard({
        label: 'Run macro',
        entityType: DragAndDropBulkEntityType.Macro,
        circle: true,
      })
      expect(wrapper.html()).toContain('rounded-full')
    })

    it('does not apply rounded-full styling when false', () => {
      const wrapper = renderCard({
        label: 'Run macro',
        entityType: DragAndDropBulkEntityType.Macro,
        circle: false,
      })
      expect(wrapper.html()).not.toContain('rounded-full')
    })
  })
})
