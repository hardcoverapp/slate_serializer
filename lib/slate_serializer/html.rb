require 'nokogiri'

module SlateSerializer
  # Html de- and serializer
  class Html
    # Default lookup list to convert html tags to object types
    ELEMENTS = {
      'a': 'link',
      'img': 'image',
      'li': 'list-item',
      'p': 'paragraph',
      'div': 'paragraph',
      'ol1': 'ordered-list',
      'ola': 'alpha-ordered-list',
      'ol': 'ordered-list',
      'ul': 'unordered-list',
      'table': 'table',
      'tbody': 'tbody',
      'tr': 'tr',
      'td': 'td',
      'text': 'text',
      'hr': 'hr',
      'figure': 'figure',
      'figcaption': 'figcaption'
    }.freeze
    # Default block types list
    BLOCK_ELEMENTS = %w[figure figcaption hr img li p ol ul table tbody tr td].freeze
    # Default inline types list
    INLINE_ELEMENTS = %w[a].freeze
    # Default mark types list
    MARK_ELEMENTS = {
      'em': 'italic',
      'strong': 'bold',
      'u': 'underline'
    }.freeze

    class << self
      # Convert html to a Slate document
      #
      # @param html format [String] the HTML
      # @param options [Hash]
      # @option options [Array] :elements Lookup list to convert html tags to object types
      # @option options [Array] :block_elemnts List of block types
      # @option options [Array] :inline_elemnts List of inline types
      # @option options [Array] :mark_elemnts List of mark types
      def deserializer(html, options = {})
        return empty_state if html.nil? || html == ''

        self.elements = options[:elements] || ELEMENTS
        self.block_elements = options[:block_elements] || BLOCK_ELEMENTS
        self.inline_elements = options[:inline_elements] || INLINE_ELEMENTS
        self.mark_elements = options[:mark_elements] || MARK_ELEMENTS

        html = html.gsub('<br>', "\n")
        nodes = Nokogiri::HTML.fragment(html).elements.map do |element|
          element_to_node(element)
        end

        {
          document: {
            object: 'document',
            children: nodes
          }
        }
      end

      # Convert html to a Slate document
      #
      # @param value format [Hash] the Slate document
      # @return [String] plain text version of the Slate documnent
      def serializer(value)
        return '' unless value.key?(:document)

        serialize_node(value[:document])
      end

      private

      attr_accessor :elements, :block_elements, :inline_elements, :mark_elements

      def element_to_node(element)
        type = convert_name_to_type(element)

        nodes = element.children.flat_map do |child|
          if block?(child)
            element_to_node(child)
          elsif inline?(child)
            element_to_inline(child)
          else
            next if child.text.strip == ''

            element_to_texts(child)
          end
        end.compact

        nodes << { object: 'text', text: '' } if nodes.empty? && type != 'image'

        {
          data: element.attributes.each_with_object({}) { |a, h| h[a[1].name] = a[1].value },
          object: 'block',
          children: nodes,
          type: type
        }
      end

      def element_to_inline(element)
        type = convert_name_to_type(element)
        nodes = element.children.flat_map do |child|
          element_to_texts(child)
        end

        {
          data: element.attributes.each_with_object({}) { |a, h| h[a[1].name] = a[1].value },
          object: 'inline',
          children: nodes,
          type: type
        }
      end

      def element_to_texts(element)
        nodes = []
        mark = convert_name_to_mark(element.name)

        if element.class == Nokogiri::XML::Element
          element.children.each do |child|
            nodes << element_to_text(child, mark)
          end
        else
          nodes << element_to_text(element)
        end

        nodes
      end

      def element_to_text(element, mark = nil)
        marks = [mark, convert_name_to_mark(element.name)].compact

        combined_marks = marks.reduce({}) do |accum, mark|
          accum.merge({
            "#{mark}": true
          })
        end

        combined_marks.merge({
          object: 'text',
          text: element.text
        })
      end

      def convert_name_to_type(element)
        type = [element.name, element.attributes['type']&.value].compact.join
        elements[type.to_sym] || elements[:p]
      end

      def convert_name_to_mark(name)
        type = mark_elements[name.to_sym]

        return nil unless type

        # ex: "bold"
        return type
      end

      def block?(element)
        block_elements.include?(element.name)
      end

      def inline?(element)
        inline_elements.include?(element.name)
      end

      def empty_state
        {
          document: {
            object: 'document',
            children: [
              {
                data: {},
                object: 'block',
                type: 'paragraph',
                children: [
                  {
                    object: 'text',
                    text: ''
                  }
                ]
              }
            ]
          }
        }
      end

      def serialize_node(node)
        if node[:object] == 'document'
          node[:children].map { |n| serialize_node(n) }.join
        elsif node[:object] == 'block'
          children = node[:children].map { |n| serialize_node(n) }.join

          element = ELEMENTS.find { |_, v| v == node[:type] }[0]
          data = node[:data].map { |k, v| "#{k}=\"#{v}\"" }

          if %i[ol1 ola].include?(element)
            data << ["type=\"#{element.to_s[-1]}\""]
            element = :ol
          end

          "<#{element}#{!data.empty? ? " #{data.join(' ')}" : ''}>#{children}</#{element}>"
        else
          node[:text]
        end
      end
    end
  end
end
