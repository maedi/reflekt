################################################################################
# Aggregate control metadata into rule sets.
# Validate reflections against aggregated controls.
#
# @pattern Singleton
#
# @hierachy
#   1. RuleSetAggregator <- YOU ARE HERE
#   2. RuleSet
#   3. Rule
################################################################################

require_relative 'rule_set'

module Reflekt
  class RuleSetAggregator
    ##
    # @param meta_map [Hash] The rules that apply to each meta type.
    ##
    def initialize(meta_map)
      @meta_map = meta_map
      # Key rule sets by class and method.
      @rule_sets = {}
    end

    ##
    # Create aggregated rule sets from control metadata.
    #
    # @stage Called on setup.
    # @param controls [Array] Controls with metadata.
    ##
    def train(controls)
      # On first use there are no previously existing controls.
      return if controls.nil?

      controls.each do |control|
        # TODO: Remove once "Fix Rowdb.get(path)" bug fixed.
        control = control.transform_keys(&:to_sym)

        klass = control[:class].to_sym
        method = control[:method].to_sym

        ##
        # INPUT
        ##

        # Singular null input.
        if control[:inputs].nil?
          train_input(klass, method, nil, 0)
        # Multiple inputs.
        else
          control[:inputs].each_with_index do |meta, arg_num|
            train_input(klass, method, meta, arg_num)
          end
        end

        ##
        # OUTPUT
        ##

        # Get rule set.
        output_rule_set = get_output_rule_set(klass, method)
        if output_rule_set.nil?
          output_rule_set = RuleSet.new(@meta_map)
          set_output_rule_set(klass, method, output_rule_set)
        end

        # Train on metadata.
        output_rule_set.train(Meta.deserialize(control[:output]))
      end
    end

    def train_input(klass, method, meta, arg_num)
      # Get deserialized meta.
      meta = Meta.deserialize(meta)

      # Get rule set.
      rule_set = get_input_rule_set(klass, method, arg_num)
      if rule_set.nil?
        rule_set = RuleSet.new(@meta_map)
        set_input_rule_set(klass, method, arg_num, rule_set)
      end

      # Train on metadata.
      rule_set.train(meta)
    end

    ##
    # Validate inputs.
    #
    # @stage Called when validating a control reflection.
    # @param inputs [Array] The method's arguments.
    # @param input_rule_sets [Array] The RuleSets to validate each input with.
    ##
    def test_inputs(inputs, input_rule_sets)
      # Default result to PASS.
      result = true

      # Validate each argument against each rule set for that argument.
      inputs.each_with_index do |input, arg_num|

        unless input_rule_sets[arg_num].nil?
          rule_set = input_rule_sets[arg_num]
          unless rule_set.test(input)
            result = false
          end
        end
      end

      result
    end

    ##
    # Validate output.
    #
    # @stage Called when validating a reflection.
    # @param output [Dynamic] The method's return value.
    # @param output_rule_set [RuleSet] The rule set to validate the output with.
    ##
    def test_output(output, output_rule_set)
      # Default to a PASS result.
      result = true

      unless output_rule_set.nil?
        # Validate output rule set for that argument.
        unless output_rule_set.test(output)
          result = false
        end
      end

      result
    end

    ##
    # Get aggregated RuleSets for all inputs.
    #
    # @stage Called when building a reflection.
    # @param klass [Symbol]
    # @param method [Symbol]
    # @return [Array]
    ##
    def get_input_rule_sets(klass, method)
      @rule_sets.dig(klass, method, :inputs)
    end

    ##
    # Get an aggregated RuleSet for an output.
    #
    # @stage Called when building a reflection.
    # @param klass [Symbol]
    # @param method [Symbol]
    # @return [RuleSet]
    ##
    def get_output_rule_set(klass, method)
      @rule_sets.dig(klass, method, :output)
    end

    ##
    # Get the base rule type for a data type.
    ##
    def self.value_to_rule_type(value)
      data_type = value.class

      rule_types = {
        Array      => ArrayRule,
        TrueClass  => BooleanRule,
        FalseClass => BooleanRule,
        Float      => FloatRule,
        Integer    => IntegerRule,
        NilClass   => NullRule,
        String     => StringRule
      }

      rule_types[data_type]
    end

    def self.testable?(args, input_rule_sets)
      args.each_with_index do |arg, arg_num|
        rule_type = value_to_rule_type(arg)
        if input_rule_sets[arg_num].rules[rule_type].nil?
          return false
        end
      end

      true
    end

    ##############################################################################
    # HELPERS
    ##############################################################################

    private

    ##
    # Get an aggregated RuleSet for an input.
    #
    # @param klass [Symbol]
    # @param method [Symbol]
    # @return [RuleSet]
    ##
    def get_input_rule_set(klass, method, arg_num)
      @rule_sets.dig(klass, method, :inputs, arg_num)
    end

    ##
    # Set an aggregated RuleSet for an input.
    #
    # @param klass [Symbol]
    # @param method [Symbol]
    ##
    def set_input_rule_set(klass, method, arg_num, rule_set)
      # Set defaults.
      @rule_sets[klass] = {} unless @rule_sets.key? klass
      @rule_sets[klass][method] = {} unless @rule_sets[klass].key? method
      @rule_sets[klass][method][:inputs] = [] unless @rule_sets[klass][method].key? :inputs
      # Set value.
      @rule_sets[klass][method][:inputs][arg_num] = rule_set
    end

    ##
    # Set an aggregated RuleSet for an output.
    #
    # @param klass [Symbol]
    # @param method [Symbol]
    # @param rule_set [RuleSet]
    ##
    def set_output_rule_set(klass, method, rule_set)
      # Set defaults.
      @rule_sets[klass] = {} unless @rule_sets.key? klass
      @rule_sets[klass][method] = {} unless @rule_sets[klass].key? method
      # Set value.
      @rule_sets[klass][method][:output] = rule_set
    end
  end
end
