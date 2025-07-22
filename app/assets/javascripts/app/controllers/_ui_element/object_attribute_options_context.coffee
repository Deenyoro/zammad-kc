# coffeelint: disable=camel_case_classes
class App.UiElement.object_attribute_options_context extends Spine.Module
  @render: (attribute, params = {}) ->
    related_object_attribute = @fetchObjectManagerAttribute(attribute)

    if !related_object_attribute
      return console.error('Related object attribute not found', attribute.object_attribute_object, attribute.object_attribute_name)

    allFlatOptions = @buildOptions(related_object_attribute)

    optionsSelected = []
    if attribute.value
      optionsSelected = @buildOptionsSelected(attribute, allFlatOptions)

    item = $(App.view('generic/object_attribute_options_context')(
      attribute:              attribute,
      valueRaw:               JSON.stringify(attribute.value || {}),
      optionsSelected:        optionsSelected,
      limitActive:            optionsSelected.length > 0 || !_.isObject(attribute.value),
      objectAttributeDisplay: related_object_attribute.display or __('Name')
    ))

    item.find('input[type="checkbox"]').off('click').on('click', ->
      item.find('.js-objectAttributeOptionsContextListContainer, .js-objectAttributeOptionsContextLimitDescription').toggleClass('hide')
      item.find('.js-objectAttributeOptionsContext').val(JSON.stringify({}))

      item.find('tr[data-id]').remove()
    )

    item.off('click', '.js-add'   ).on('click', '.js-add',    (e) => @onAdd(e, item, attribute.name, related_object_attribute, allFlatOptions))
    item.off('click', '.js-remove').on('click', '.js-remove', (e) => @onRemove(e, item, attribute.name, related_object_attribute, allFlatOptions))

    @renderOptionDropdownNew(item, attribute.name, related_object_attribute, allFlatOptions)

    item

  @renderOptionDropdownNew: (item, name, related_object_attribute, allFlatOptions) ->
    filteredOptionValues = @getFilteredOptionValues(item, allFlatOptions)

    attribute = {
      nulloption: true,
      null:       true,
      id:         'attribute-' + name + '-search',
      filter:     filteredOptionValues,
    }

    if related_object_attribute.relation
      attribute.relation = related_object_attribute.relation
    else
      attribute.options = related_object_attribute.options

    element = App.UiElement.ApplicationTreeSelect.render(attribute)

    item.find('.js-objectAttributeOptionsContextItemAddNew').html(element)
    element.find('.js-shadow').trigger('change')

  @getFilteredOptionValues: (item, allOptions) ->
    return if !allOptions || Object.keys(allOptions).length == 0


    currentValue = @getCurrentValue(item)
    selectedValues = Object.keys(currentValue)

    Object.keys(allOptions)
      .filter (optionValue) -> !_.include(selectedValues, optionValue)
      .map    (optionValue) -> optionValue

  @onAdd: (e, item, name, related_object_attribute, allFlatOptions) ->
    e.stopPropagation()
    e.preventDefault()

    newOptionValue = item.find('.js-shadow').val()

    $(e.target.closest('tr')).find('.js-input').toggleClass('has-error', !newOptionValue)
    return if !newOptionValue

    displayValue = allFlatOptions[newOptionValue]
    return if !displayValue

    shadowRow = item.find('.js-objectAttributeOptionsContextShadowItemRow')

    newRow = shadowRow
      .clone()
      .removeClass('hide js-objectAttributeOptionsContextShadowItemRow')
      .attr('data-id', newOptionValue)

    newRow.find('td:first-child').text(displayValue)

    newRow.insertBefore(shadowRow)

    @addValue(item, newOptionValue)

    @renderOptionDropdownNew(item, name, related_object_attribute, allFlatOptions)

  @onRemove: (e, item, name, related_object_attribute, allFlatOptions) ->
    e.stopPropagation()
    e.preventDefault()

    # Get the row ID before removing the row
    rowId = $(e.target).closest('tr').attr('data-id')

    e.target
      .closest('tr')
      .remove()

    @removeValue(item, rowId)

    @renderOptionDropdownNew(item, name, related_object_attribute, allFlatOptions)

  @getCurrentValue: (item) ->
    currentValue = {}

    try
      currentValue = JSON.parse(item.find('.js-objectAttributeOptionsContext').val()) || {}
    catch e
      currentValue = {}

    currentValue

  @addValue: (item, value) ->
    currentValue = @getCurrentValue(item)

    # Add the value to the current value without any content yet (maybe later a description).
    currentValue[value] = ''

    item.find('.js-objectAttributeOptionsContext').val(JSON.stringify(currentValue))

  @removeValue: (item, value) ->
    currentValue = @getCurrentValue(item)

    delete currentValue[value.toString()]

    item.find('.js-objectAttributeOptionsContext').val(JSON.stringify(currentValue))

  @fetchObjectManagerAttribute: (attribute) ->
    App[attribute.object_attribute_object].configure_attributes.find((elem) -> elem.name == attribute.object_attribute_name)

  @buildOptions: (related_object_attribute) ->
    if related_object_attribute.relation
      itemsRaw = App[related_object_attribute.relation].search(sortBy: 'name')
      activeItems = itemsRaw.filter (elem) -> elem.active
      optionsHash = {}
      activeItems.forEach (item) ->
        optionsHash[item.id.toString()] = item.displayName()
      return optionsHash
    else
      if _.isArray(related_object_attribute.options)
        return @buildFlatOptions(related_object_attribute.options)
      else
        return related_object_attribute.options

  @buildOptionsSelected: (attribute, allFlatOptions) ->
    optionsSelected = []

    Object.keys(attribute.value).forEach (value) ->
      if allFlatOptions[value]
        optionsSelected.push(
          {
            value: value,
            label: allFlatOptions[value]
          }
        )

    optionsSelected

  @buildFlatOptions: (options) ->
    optionsHash = {}

    options.forEach (option) ->
      optionsHash[option.value] = option.value.replaceAll('::', ' › ')

      if option.children
        childOptions = App.UiElement.object_attribute_options_context.buildFlatOptions(option.children)
        Object.assign(optionsHash, childOptions)

    return optionsHash
